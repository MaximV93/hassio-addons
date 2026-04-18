# hass-sma-rs

[![Version](https://img.shields.io/badge/version-0.1.37-blue)](config.yaml)
![Arch](https://img.shields.io/badge/arch-amd64%20%7C%20aarch64-success)
![Stage](https://img.shields.io/badge/stage-experimental-orange)

SMA Sunny Boy Bluetooth monitor — Rust rewrite.

## What this is

Home Assistant addon that talks directly to SMA Sunny Boy inverters over
Bluetooth (RFCOMM) and publishes 27 sensors per inverter to MQTT with
full HA auto-discovery.

Clean-room Rust implementation of the SMA BT protocol — no dependency on
the upstream C++ SBFspot binary. Written and fully validated against a
live SB 3000HF-30 in 24 hours of iteration on 2026-04-17 / 18.

## Why

- **Faster data** — persistent BT session, no 5 s handshake tax per poll
- **Stays quiet at night** — adaptive 10-min backoff when inverter sleeps
- **MQTT LWT** — sensors flip to `unavailable` when daemon/broker dies
- **27 sensors** — per-phase AC + per-string DC (not just aggregates)
- **Prometheus `:9090/metrics`** — 15 metric families for Grafana
- **Type-safe Rust** — 54 unit + integration tests, 290 captured-frame fixture suite

## Install

Repositories → Add → `https://github.com/MaximV93/hassio-addons` → install
**hass-sma-rs (Rust rewrite)**.

## Configure

```yaml
mqtt:
  host: core-mosquitto
  port: 1883
  user: sbfspot
  password: "<mqtt password>"

inverters:
  - slot: zolder
    bt_address: "00:80:25:21:32:35"
    password: "<inverter user password>"
    poll_interval: 60s
    model: "SB 3000HF-30"
    firmware: "02.30.06.R"
    # Parallel-run with haos-sbfspot or another SMA integration:
    # yield_every: 10
    # yield_duration: 60s

local_bt_address: "04:42:1A:5A:37:74"
rfcomm_timeout: 15s
metrics_addr: "0.0.0.0:9090"
```

Multiple inverters = multiple `inverters:` entries. Each gets its own
tokio task with independent session + backoff.

## Sensors (per inverter)

Entity IDs follow `sensor.sbfspot_<slot>_<metric>`.

**AC**: `ac_power`, `ac_power_l{1,2,3}`, `ac_voltage_l{1,2,3}`,
`ac_current_l{1,2,3}`, `grid_frequency`

**DC**: `dc_power_string_{1,2}`, `dc_voltage_string_{1,2}`,
`dc_current_string_{1,2}`

**Energy**: `energy_today`, `energy_lifetime`, `operation_time`,
`feed_in_time`

**Diagnostics**: `inverter_temperature`, `inverter_status_2` (health),
`poll_status` (daemon cycle), `grid_relay`, `firmware_version`,
`inverter_model`, `last_poll`

Every sensor references `hass-sma/<slot>/availability` so HA marks them
`unavailable` on daemon/broker loss.

## Comparison

See [`COMPARISON.md`](https://github.com/MaximV93/hass-sma-rs/blob/master/docs/COMPARISON.md)
for the three-way feature matrix vs stock SBFspot and haos-sbfspot fork.

## Source

- Rust daemon: <https://github.com/MaximV93/hass-sma-rs>
- Protocol reference: [SBFspot](https://github.com/SBFspot/SBFspot) (CC BY-NC-SA)

## Troubleshooting

- `connect failed: Host is down (os error 112)` — inverter BT powered off
  (sunset). Normal. Adaptive backoff extends to 10 min. Sensors flip
  `unavailable` via LWT.
- `connect failed: Resource busy (os error 16)` — another addon (e.g.
  haos-sbfspot) is holding the BT. Set `yield_every` + `yield_duration`
  to share nicely.
- Sensor stuck on old value — clear the retained MQTT topic or restart
  the addon.

Logs: `RUST_LOG=debug` (default in this addon) logs every frame and
query. Look for `query reply` and `handshake/logon` lines.
