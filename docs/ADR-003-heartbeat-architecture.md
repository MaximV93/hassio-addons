# ADR-003: Four-sensor heartbeat architecture

**Status**: Accepted  
**Date**: 2026-04-17  
**Release**: `haos-sbfspot` 2026.4.17.5 (implemented), 2026.4.17.8 (completed with hang_count)

## Context

We need to detect two distinct failure modes in Home Assistant:

1. **Polling stopped entirely** — cron daemon died, addon crashed, no SBFspot runs firing.
2. **Polling fires but SBFspot itself is broken** — cron runs, SBFspot is invoked, but BT is unreachable / inverter unresponsive / hangs mid-session.

Upstream had only one signal: `sensor.haos_sbfspot_sma_timestamp`, populated from the JSON payload of a successful SBFspot publish. When SBFspot hangs or fails, this sensor freezes. You can't tell from the outside whether the addon crashed or just can't reach the inverter.

## Decision

Publish **four** MQTT-discovered diagnostic sensors from the addon, each providing a different axis of the health picture:

| Sensor | Signal | Updated by |
|---|---|---|
| `cron_heartbeat` (timestamp) | cron is alive and firing | Every minute, 24/7 |
| `last_run_status` (enum: ok/hang/failed-N/missing) | last SBFspot invocation outcome | After each SBFspot run |
| `hang_count` (total_increasing) | how many times the timeout wrapper SIGKILL'd SBFspot | On each hang (exit 137 or 124) |
| `last_run_duration` (seconds) | how long the last SBFspot run took | After each SBFspot run |

Both the `cron_heartbeat` and `last_run_status` are free standing, independent signals. Crossing them (automation) is where the insight lives:

- `cron_heartbeat` fresh **and** `sma_timestamp` fresh → healthy
- `cron_heartbeat` fresh **but** `sma_timestamp` stale (>3× poll interval) → SBFspot is running but failing silently → alert
- `cron_heartbeat` stale → addon itself is down → alert

## Rationale

### Why four sensors, not one

Could we just bake status, duration, and timestamp into one JSON sensor? Yes. But:

- Home Assistant's dashboard tile cards bind to scalar sensors. Making users parse JSON defeats the point.
- Energy dashboards and automations want single-value sensors with device_class.
- Timestamp sensor with `device_class: timestamp` renders "X seconds ago" natively, perfect for at-a-glance freshness.
- `state_class: total_increasing` on `hang_count` makes it graphable as a counter (HA statistics engine).
- `state_class: measurement` on `last_duration` graphs cleanly as a line chart.

### Why MQTT discovery

The alternative is to define YAML sensors in `configuration.yaml` (or a template). Three reasons MQTT discovery is better:

1. **Distribution**: the addon ships its own discovery, no user-side config needed. Install → sensors appear.
2. **Lifecycle**: Discovery is retained MQTT; HA picks it up at any time regardless of restart order.
3. **Separation**: The addon owns the sensor definitions. If we add a 5th metric in v4, users don't need to update YAML.

### Why independent publishers

The heartbeat publisher (`publish-heartbeat.sh`) is a dedicated cron entry running every minute with no gating on time-of-day or other options. This separates cron's "am I running?" signal from SBFspot's "did my last run succeed?" signal.

## Architecture

```
cron daemon
  ├─ * * * * *  publish-heartbeat.sh
  │            → reads /data/sbfspot_status.json  (updated by run-sbfspot.sh)
  │            → mosquitto_pub homeassistant/sbfspot/{cron_heartbeat,last_status,hang_count,last_duration}
  │
  ├─ @reboot sleep 30 && run-sbfspot.sh reboot timeout -s KILL N SBFspot …
  ├─ */1 6-22 * * *    run-sbfspot.sh day    timeout -s KILL N SBFspot …
  ├─ */15 23-5 * * *   run-sbfspot.sh night  timeout -s KILL N SBFspot …
  └─ 55 05 * * *       run-sbfspot.sh archive timeout -s KILL 300 SBFspot …

run-sbfspot.sh:
  1. tee stdout/stderr to /data/logs/sbfspot-YYYY-MM-DD.log
  2. on exit, jq-merge /data/sbfspot_status.json with {last_run_kind, last_run_end, last_run_exit, ...}
  3. exit 137 or 124 → increment hang_count, tag last_failure_reason = hang-killed-by-timeout

publish-heartbeat.sh reads status.json, publishes current values to MQTT every minute.
```

Discovery configs are published once by `cont-init.d/02-publish-heartbeat-discovery.sh` (retained), so HA can auto-create the entities at any point after first addon start.

## Consequences

- HA entity IDs are uglified by HA's device-based naming: `sensor.haos_sbfspot_powerslider_sbfspot_cron_heartbeat` rather than `sensor.sbfspot_cron_heartbeat`. This is a function of having a `device:` block in the discovery config. A future cleanup (ADR-005 candidate) can add `object_id` to the discovery to override, at the cost of breaking existing dashboards that reference current IDs.
- One extra cron job per minute (the heartbeat publisher). Trivial load.
- `/data/sbfspot_status.json` is an ephemeral state file. Survives addon restart but not uninstall. Acceptable.

## Code references

- `haos-sbfspot/rootfs/etc/cont-init.d/02-publish-heartbeat-discovery.sh` — one-shot discovery publish
- `haos-sbfspot/rootfs/usr/bin/sbfspot/publish-heartbeat.sh` — per-minute data publish
- `haos-sbfspot/rootfs/usr/bin/sbfspot/run-sbfspot.sh` — status.json writer
- `haos-sbfspot/rootfs/etc/cont-init.d/01-generate-crontab.sh` — cron entry for publish-heartbeat
