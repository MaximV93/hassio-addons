# hass-sma-rs

SMA Sunny Boy BT inverter daemon — Rust rewrite of SBFspot's Bluetooth path.

## What this replaces

A drop-in replacement for `haos-sbfspot` (the fork of the upstream SBFspot
addon). Instead of running `SBFspot` as a subprocess every N minutes, this
addon keeps a **persistent BT session** and polls metrics continuously.

## Feature comparison

| Feature | haos-sbfspot | hass-sma-rs |
|---|---|---|
| Language | C++ / bash | Rust |
| BT session | reopened every poll (~5 s startup cost) | persistent |
| MQTT sensors | ~15 via `Sensors_HA=Create` | **25** (3-phase AC + per-string DC split) |
| MQTT availability (LWT) | ❌ | ✅ — sensors flip to `unavailable` on daemon loss |
| Sleep detection | fixed poll interval | **adaptive** — 10 min backoff after 3 `Host is down` |
| Prometheus `/metrics` | ❌ | ✅ on port 9090 — 15 metric families |
| Live reload | restart addon | restart addon |
| Handshake | forks `SBFspot` binary | native Rust reverse-engineering, 52 unit tests + 290-frame fixture suite |

## Configuration

```yaml
mqtt:
  host: core-mosquitto
  port: 1883
  user: sbfspot
  password: <secret>
  client_id: hass-sma-rs
  discovery_prefix: homeassistant
  state_prefix: hass-sma

inverters:
  - slot: zolder
    bt_address: "00:80:25:21:32:35"
    password: "sZ4kmKTxOdHN"
    poll_interval: 60s
    model: "SB 3000HF-30"
    firmware: "02.30.06.R"
    mis_enabled: false

local_bt_address: "04:42:1A:5A:37:74"   # HCI adapter MAC (optional)
rfcomm_timeout: 15s
metrics_addr: "0.0.0.0:9090"
```

Each inverter gets its own BT session task with independent backoff.

## Published MQTT sensors (per inverter)

**AC side**
- `ac_power` (W, total)
- `ac_power_l1`, `ac_power_l2`, `ac_power_l3`
- `ac_voltage_l1..3`
- `ac_current_l1..3`
- `grid_frequency` (Hz)

**DC side**
- `dc_power_s1`, `dc_power_s2`
- `dc_voltage_s1`, `dc_voltage_s2`
- `dc_current_s1`, `dc_current_s2`

**Energy**
- `energy_today` (kWh)
- `energy_lifetime` (kWh)
- `operation_time` (h)
- `feed_in_time` (h)

**Diagnostics**
- `temperature` (°C)
- `status` (text: Ok / Warning / Error / Off)
- `grid_relay` (text: closed / open)
- `firmware_version` (text, e.g. `02.30.06.R`)
- `last_poll` (ISO 8601 timestamp of last successful sweep)

Every sensor references a per-inverter `availability_topic`
(`hass-sma/<slot>/availability`) so HA flips them to `unavailable` when the
daemon disconnects.

## Prometheus metrics (`:9090/metrics`)

- `sma_polls_total{slot}`
- `sma_poll_errors_total{slot}`
- `sma_bt_reconnects_total{slot}`
- `sma_handshake_errors_total{slot}`
- `sma_inverter_awake{slot}` (1/0)
- `sma_last_successful_poll_unix{slot}`
- `sma_ac_power_watts{slot}`, `sma_ac_voltage_l1{slot}`, `sma_ac_current_l1{slot}`
- `sma_grid_frequency_hz{slot}`
- `sma_dc_power_s1_watts{slot}`, `sma_dc_power_s2_watts{slot}`
- `sma_inverter_temperature_c{slot}`
- `sma_energy_today_wh{slot}`, `sma_energy_lifetime_wh{slot}`

## Adaptive reconnect

SMA inverters power off their BT radio ~60–90 min after sunset. A naive poll
loop burns BT bandwidth all night trying to reconnect. This daemon:

1. First 3 connect failures: exponential backoff 2s → 4s → 8s → 16s → 32s → 60s
2. On 3 consecutive `Host is down` (EHOSTDOWN) errors → switch to **10 min
   sleep-backoff**, publish `offline` to MQTT availability, stop spamming logs
3. Next successful connect → back to normal polling, publish `online`

## Parallel-run with haos-sbfspot

Safe to run both addons simultaneously during migration — BT sessions serialize
via BlueZ. This addon takes a few seconds longer to connect when haos-sbfspot
is mid-poll.

## Troubleshooting

- `logon failed (code 0x0100)`: wrong inverter password
- `handshake/logon failed: unexpected L2 payload shape`: protocol mismatch —
  capture bytes via `RUST_LOG=debug`, file issue with hex dumps
- `Host is down` at sundown: normal, daemon backs off automatically

## Source

- Rust crate: <https://github.com/MaximV93/hass-sma-rs>
- Protocol reference: SBFspot (<https://github.com/SBFspot/SBFspot>, CC BY-NC-SA)
- 290 captured wire frames in `tests/fixtures/captured/`
