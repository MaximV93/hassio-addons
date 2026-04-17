# SBFspot hang analysis (V3-02)

**Status**: Data collection started 2026-04-17 ~09:40 UTC (deployed with `haos-sbfspot` 2026.4.17.8). Revisit at baseline + 7 days for meaningful statistics.

## What we're tracking

Three sensors expose hang behavior:

| Entity | Signal |
|---|---|
| `sensor.sbfspot_hang_count` | Monotonically increasing counter of SBFspot runs killed by `timeout -s KILL` (exit 137 or 124) |
| `sensor.sbfspot_last_run_status` | Most recent outcome: `ok`, `hang`, `failed-N`, `missing` |
| `sensor.sbfspot_last_run_duration` | Duration (seconds) of most recent run |

Persistent log `/data/logs/sbfspot-YYYY-MM-DD.log` records every SBFspot invocation with stdout, marked with `=== [timestamp] kind HANG: killed after Ns (exit RC)` on hangs.

## Initial observations (2026-04-17, first ~2h of v2e runtime)

```
Deployment:         2026-04-17T09:40 UTC (haos-sbfspot 2026.4.17.8)
First hang:        ~09:40 (likely @reboot run, BT session setup with
                    MIS mode hitting all 3 devices)
Second hang:       ~10:07
Normal run dur:     16-32s (well under 50s timeout)
hang rate so far:  ~1 / hour during 06-22 daytime window
```

Two hangs in the first 2 hours of runtime. Extrapolation: ~16 hangs/day worst-case, or ~1.1% of all polls (at 1-min polling → 960 polls/day). Acceptable if stable. Concerning if it rises.

## Known variables

What we think correlates with hangs:

1. **MIS mode with 3 BT devices** (2 inverters + repeater). SBFspot iterates all devices in one session; one unresponsive device stalls the whole run.
2. **Marginal BT signal** on the zolder inverter (RSSI -80 to -90 dBm measured in the `bluetoothctl scan`). Single-digit-% `BTSignal` in the logs. Border of reliability.
3. **Repeater as a "device"** in MIS. SBFspot queries it with the same spot-data requests as an inverter; repeater doesn't respond like an inverter and may time out internally before our wrapper fires.

What we've ruled out so far:

- **Upstream cron race** — no flock anymore; each tick has a fresh slate.
- **MQTT broker slowness** — publish times are sub-second; SBFspot's internal wait is the bottleneck.
- **Container resource pressure** — `ha_get_addon(include_stats=True)` shows CPU <5%, memory <30 MB. Not host-level issue.

## Diagnostic procedure

When investigating a hang event:

1. **Identify the run** — find the hang timestamp in `sensor.sbfspot_last_run_status` history (was `hang` at some minute).
2. **Fetch persistent log** for that date: `/data/logs/sbfspot-YYYY-MM-DD.log` via Samba share on HA host.
3. **Find the HANG block**:
   ```bash
   grep -B 20 -A 2 'HANG:' /data/logs/sbfspot-2026-04-17.log
   ```
4. **Read what SBFspot was doing before the kill**. Example pattern suggestive of repeater hang:
   ```
   SUSyID: 102 - SN: 170004597           ← repeater
   Packet status: -1                      ← no response from last request
   Packet status: -1
   Packet status: -1
   === HANG: killed after 50s (exit 137)
   ```
5. **Correlate** with `sensor.haos_sbfspot_sma_bluetooth_signal` history at the same time. Marginal signal → expected. Strong signal → something structural.

## Hypotheses to test (v3 or later)

| Hypothesis | Test | If confirmed → fix |
|---|---|---|
| BTConnectRetries too high (default 10) | Lower to 3, observe hang rate over 7d | Ship lower default |
| Repeater causing MIS stalls | Try `MIS_Enabled: false` + single-inverter loop, measure hang rate per-inverter | Exclude repeater via upstream patch |
| Specific device always culprit | Parse /data/logs for SN of last SUSyID before each HANG | Per-device timeout / skip-on-failure |
| Daily pattern (e.g. near sunset with weak signal) | Chart hangs by hour of day | SunRSOffset increase / tighter day window |

## Revisit criteria

Check `sensor.sbfspot_hang_count` value at:

- T+24h, T+7d, T+14d. Record value in this doc.
- If rate > 5/hour sustained: escalate to v4 investigation.
- If rate < 1/day: consider this noise-floor and close the investigation.

## Log

| Date | Elapsed | `hang_count` | Notes |
|---|---|---|---|
| 2026-04-17 09:40 UTC | 0 h | 0 (baseline) | v2e deployed |
| 2026-04-17 ~12:17 UTC | +2.5 h | 2 | Spot check; v1.1 of this doc written |
