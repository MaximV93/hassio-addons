# ADR-004: Sub-minute polling via in-process daemon

**Status**: Accepted
**Date**: 2026-04-17
**Release**: `haos-sbfspot` 2026.4.17.14

## Context

Upstream + our v3 fork use **cron** (`busybox crond`) for the SBFspot polling
loop. Cron's minimum resolution is 1 minute. Users (us) sometimes want
sub-minute polling — e.g. 5 s to approach SMA's internal sampling rate and
see sharper solar production curves without 1-minute quantization.

Cron cannot be coerced below 1 min without external schedulers. Options
considered:

1. **Fractional crontab hacks** (e.g. `*/1 * * * * /run.sh && sleep 15 && /run.sh`) — brittle, opaque, loses overlap detection.
2. **systemd timer** — not available in Alpine addon base.
3. **External scheduler sidecar** (ofelia, gocron) — adds a binary, extra attack surface, config sprawl.
4. **In-process daemon** (this ADR) — a tight bash `while` loop running as an s6-overlay long-run service. Same idiom s6 uses elsewhere in HA addons.

## Decision

Add option `PollIntervalSec: int(0,3600)` (default **0** = disabled).

- `PollIntervalSec == 0` → legacy cron path, unchanged. `PollIntervalDay` + `PollIntervalNight` drive cron entries. No behavioural change for existing installs.
- `PollIntervalSec >= 5` → daemon path:
  - A new s6 service `services.d/sbfspot-poller/run` takes over the day/night polling loop.
  - `cont-init.d/01-generate-crontab.sh` *skips* the day/night cron entries (keeps heartbeat, archive, upload, hang-analyzer).
  - Archive poll, MQTT heartbeat, hang analyzer, and PVOutput uploader remain cron-driven.
- `PollIntervalSec` **< 5 (but > 0)** → treated as disabled, the poller service tail-sleeps so s6 keeps it "alive" without respawning. 5 s is the floor because SMA inverters sample their internal state at roughly that cadence; sub-5 s wastes BT airtime reading duplicate values.

Companion option `PollIntervalNightSec: int(0,3600)` mirrors the legacy night-poll behaviour for the daemon path. `0` = skip nights.

## Loop invariants

```
┌────────────── daemon startup ──────────────────────────────┐
│ 1. read options.json (jq -r)                               │
│ 2. if PollIntervalSec < 5: `exec sleep infinity`           │
│ 3. wait up to 5 min for /usr/bin/sbfspot/SBFspot.cfg       │
│    (written by services.d/sbfspot/run — parallel startup)  │
│ 4. trap SIGTERM/SIGINT → set STOP=1                        │
└────────────────────────────────────────────────────────────┘
         │
         ▼
┌────────────── loop body ───────────────────────────────────┐
│  while STOP==0:                                            │
│    hour = date +%-H                                        │
│    if DAY_START <= hour <= DAY_END:                        │
│       interval = PollIntervalSec,     kind = daemon-day    │
│    elif PollIntervalNightSec >= 5:                         │
│       interval = PollIntervalNightSec, kind = daemon-night │
│    else:  sleep 60; continue              # night skip     │
│    t0 = now                                                │
│    run-sbfspot.sh <kind> timeout -s KILL <timeout> SBFspot │
│    elapsed = now - t0                                      │
│    if elapsed >= interval:                                 │
│       log "BT-saturated" (once) and continue               │
│    sleep (interval - elapsed)                              │
└────────────────────────────────────────────────────────────┘
```

## Rationale

### Why a daemon and not tighter cron hacks

Cron's minute boundary + fractional hacks means ticks are irregular (drift),
and overlap detection becomes ad-hoc. A daemon that computes
`sleep(interval - elapsed)` gives **regular spacing regardless of run time**
and trivially handles BT-saturation (just drop the sleep).

### Why s6-overlay long-run, not a backgrounded cron @reboot

s6 supervises, restarts on crash, and stops cleanly on addon stop (SIGTERM to
the service tree). A backgrounded cron process would leak on crash, have no
restart, and be invisible to `s6-svc status`.

### Why PollIntervalSec doesn't replace PollIntervalDay

Backward compatibility. Users running at 5 min polling shouldn't need to flip
an option to stay at 5 min. `0` (default) preserves the legacy cron path.
Upgraders see no change.

### Why 5 s floor

SMA HF-30 firmware samples internal values roughly every 5 s. Reading faster
produces duplicate snapshots and wastes BT airtime. The physical polling
ceiling is the real constraint (piconet connect ~5-10 s), so `PollIntervalSec`
below 5 s is enforced to 0 (disabled) rather than silently busy-looped.

### Why overlap is "just log and continue"

If SBFspot takes 30 s and interval is 5 s, we're effectively continuously
polling. That's what the user asked for. `timeout -s KILL` still protects
against hangs. `flock` would queue runs — not desired, that's worse than
continuous polling (eventually falls behind reality).

## Consequences

- **Observability same as before**: `run-sbfspot.sh` still writes
  `/data/sbfspot_status.json`, `publish-heartbeat.sh` still publishes from it.
  Cron heartbeat alone no longer proves polling is live (cron is idle for
  day/night). Use `last_status` sensor for polling liveness.
- **Log volume scales with poll rate**: at 5 s intervals, ~17 k lines/day
  per inverter. `run-sbfspot.sh` size-caps `/data/logs` at 100 MB and drops
  the oldest file when exceeded (V4, in addition to the 7-day mtime rotation).
- **BT contention risk rises** with two inverters on one piconet and
  sub-15 s polling. `SBFspotTimeoutSec` becomes the knob: increase if
  marginal signal, decrease if signal is strong and you want faster failure.
- **No breaking change for cron path**: PollIntervalSec=0 leaves v3 behaviour
  completely intact.

## Code references

- `config.yaml` — `PollIntervalSec`, `PollIntervalNightSec` options
- `rootfs/etc/cont-init.d/01-generate-crontab.sh` — skips day/night cron when `PollIntervalSec >= 5`
- `rootfs/etc/services.d/sbfspot-poller/run` — daemon loop
- `rootfs/etc/services.d/sbfspot-poller/finish` — restart-pacing
- `rootfs/usr/bin/sbfspot/run-sbfspot.sh` — called by both cron and daemon path
