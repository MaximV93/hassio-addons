# HAOS-SBFspot (powerslider fork)

Bluetooth-based polling for **SMA Sunny Boy** solar inverters (HF-30 series and compatible), publishing to Home Assistant via MQTT and optionally archiving to MariaDB + PVOutput.

> This is a [powerslider fork](https://github.com/MaximV93/hassio-addons) of `habuild/hassio-addons/haos-sbfspot`. Diffs from upstream: configurable polling, bug fixes, heartbeat sensors, persistent logs. See [FORK.md](https://github.com/MaximV93/hassio-addons/blob/main/FORK.md) for details.

## Prerequisites

- **SMA inverter** with Bluetooth (HF series, pre-2014 models). Modern Speedwire-only inverters won't work — use the official HA *SMA Solar* integration instead.
- **Bluetooth host adapter** reachable from the HA machine (USB dongle passthrough from hypervisor if HA runs on a VM).
- **MQTT broker** — the *Mosquitto broker* addon is the easy default.
- **MariaDB addon** — only required if `EnableUpload: true` (PVOutput uploader reads from DB). Skip if you just want live polling in HA.
- **Bluetooth password** for your inverter — usually `0000` by default, but installers often change it. Ask your installer, check Sunny Explorer, or reset via the inverter display.

## First-install checklist

1. Add this repository in Supervisor → Add-on store → 3-dot menu → Repositories:  
   `https://github.com/MaximV93/hassio-addons`
2. Install **HAOS-SBFspot (powerslider)** from the store.
3. Open the addon's *Configuration* tab and fill in **at minimum**:
   - `BTAddress` — inverter's Bluetooth MAC (format `00:80:25:XX:XX:XX`). Find it via `bluetoothctl scan on` on the host or a phone BT scanner.
   - `Password` — inverter user-group password.
   - `LocalBTAddress` — host BT adapter MAC (optional; autodetected).
   - `Plantname` — anything, used in MQTT topic (default `SBFspot`).
   - `Latitude` / `Longitude` — your location, for SBFspot's sunrise/sunset calculation.
   - `Timezone` — `Europe/Brussels`, `America/New_York`, etc.
   - `MQTT_User` / `MQTT_Pass` — credentials for the Mosquitto broker.
4. Start the addon.
5. (Multi-inverter only) After one successful run, set `MIS_Enabled: true` and the primary inverter's `BTAddress`; SBFspot auto-discovers secondary inverters on the same BT NetID.
6. To create Home Assistant sensors for the inverter data, set `Sensors_HA: "Create"` and restart **once**. The fork tracks this as a one-shot via `/data/.sensors_published`; it won't republish on subsequent restarts.

## Polling configuration (powerslider fork)

| Option | Default | Range | Effect |
|---|---|---|---|
| `PollIntervalDay` | 5 | 1–30 minutes | How often SBFspot runs during the daytime window |
| `PollIntervalNight` | 0 | 0–60 minutes | How often SBFspot runs outside the daytime window. `0` disables night polling. |
| `DayStart` | 6 | 0–23 hour | Daytime window start (local time) |
| `DayEnd` | 22 | 1–23 hour | Daytime window end (inclusive) |
| `EnableUpload` | true | bool | Start `SBFspotUploadDaemon` for PVOutput. Set `false` if not using PVOutput. |
| `SBFspotTimeoutSec` | 0 | 0–600 seconds | Explicit hard kill timeout per SBFspot run. `0` = auto (`PollIntervalDay*60-10`). Raise if your BT is marginal and legit runs exceed 50 s. |

## Heartbeat sensors (powerslider fork)

Four diagnostic sensors auto-published via MQTT discovery. Naming: HA prefixes with device name → `sensor.haos_sbfspot_powerslider_sbfspot_*`.

| Entity | Type | Purpose |
|---|---|---|
| `..._cron_heartbeat` | timestamp | Updated every minute regardless of SBFspot success; proves cron is alive. |
| `..._last_run_status` | enum: `ok` \| `hang` \| `failed-N` \| `missing` | Outcome of most recent SBFspot invocation. |
| `..._hang_count` | total_increasing | Number of times the timeout wrapper SIGKILL'd SBFspot. |
| `..._last_run_duration` | seconds | Duration of most recent SBFspot run. |

**Detecting silent failures**: `cron_heartbeat` fresh + `haos_sbfspot_sma_timestamp` stale (> 3× poll interval) means SBFspot is running but not publishing → alert on this in an automation.

## Persistent logs

`/data/logs/sbfspot-YYYY-MM-DD.log` — daily file, 7-day rotation. Access via the Samba share addon.

```bash
# From an SSH shell on your HA machine:
ls -la /mnt/data/supervisor/addons/data/*haos-sbfspot*/logs/
tail -100 /mnt/data/supervisor/addons/data/*haos-sbfspot*/logs/sbfspot-$(date +%Y-%m-%d).log
```

Supervisor's own addon log only keeps the last ~100 lines; for anything older, use the file.

## MIS (multi-inverter) setup

> All inverters + repeater must share the same **NetID** (not `1`). Set per-inverter via Sunny Explorer or the inverter display. NetID `1` is reserved for single-inverter installs.

1. Set `BTAddress` to any one of the inverters (doesn't matter which).
2. Set `MIS_Enabled: true`.
3. Restart addon. SBFspot queries all devices on the piconet in one session.

Secondary inverters' sensors need to be published via the separate `haos-sbfspot-sensorsgen` addon (upstream, unchanged in our fork). See that addon's docs.

## Troubleshooting

See [TROUBLESHOOTING.md](https://github.com/MaximV93/hassio-addons/blob/main/docs/TROUBLESHOOTING.md) for common failure modes and diagnostics.

Quick hits:
- **"Logon failed"** → wrong `Password`. Ask installer or try `0000` (factory default).
- **"bthConnect() returned -1"** → BT adapter not reachable. Check USB dongle pass-through; `host_network: true` must be set in addon config (default in this fork).
- **Empty data during day** → inverter asleep, grid fault, or `Plantname` doesn't match topic pattern. Check addon log.
- **Hang count rising** → BT signal marginal. See [TROUBLESHOOTING.md §7](https://github.com/MaximV93/hassio-addons/blob/main/docs/TROUBLESHOOTING.md).

## All options

See `config.yaml` for the full schema. Beyond fork-added options (see table above), all upstream SBFspot options are passed through unchanged: `MIS_Enabled`, `SynchTime`, `BTConnectRetries`, `Locale`, `CalculateMissingSpotValues`, CSV export settings, etc. Defaults match SBFspot's built-in defaults; no need to set anything you don't specifically need.

## Architectural decisions

Why certain choices were made, for the curious:

- [ADR-001: `timeout` over `flock`](https://github.com/MaximV93/hassio-addons/blob/main/docs/ADR-001-timeout-over-flock.md) — how we prevent overlap without dead-locking on hangs
- [ADR-002: `host_network: true`](https://github.com/MaximV93/hassio-addons/blob/main/docs/ADR-002-host-network-required.md) — why we can't drop it
- [ADR-003: four-sensor heartbeat](https://github.com/MaximV93/hassio-addons/blob/main/docs/ADR-003-heartbeat-architecture.md) — why a single status sensor isn't enough

## Credits

- [SBFspot](https://github.com/SBFspot/SBFspot) — the C++ polling binary (upstream of upstream)
- [habuild/hassio-addons](https://github.com/habuild/hassio-addons) — original HAOS wrapper addon this forks from
- [powerslider/hassio-addons](https://github.com/MaximV93/hassio-addons) — this fork, maintained by MaximV93
