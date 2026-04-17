# HAOS-SBFspot (powerslider fork)

Home Assistant addon — Bluetooth polling of SMA Sunny Boy inverters → MQTT → HA sensors + optional MariaDB/PVOutput archiving.

[![Version](https://img.shields.io/badge/dynamic/yaml?label=Version&query=%24.version&url=https%3A%2F%2Fraw.githubusercontent.com%2FMaximV93%2Fhassio-addons%2Fmain%2Fhaos-sbfspot%2Fconfig.yaml)](https://github.com/MaximV93/hassio-addons/tree/main/haos-sbfspot)
![Arch](https://img.shields.io/badge/arch-amd64%20%7C%20aarch64%20%7C%20armv7%20%7C%20armhf-success)
![Stage](https://img.shields.io/badge/stage-experimental-orange)

[![Open your Home Assistant instance and show the add add-on repository dialog with a specific repository URL pre-filled.](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2FMaximV93%2Fhassio-addons)

## Quick start

```
Supervisor → Add-on store → ⋮ Repositories → Add
https://github.com/MaximV93/hassio-addons

Install HAOS-SBFspot (powerslider) → Configure → Start.
```

See **[DOCS.md](./DOCS.md)** for the first-install checklist and option reference.

## What this fork adds over upstream

| Area | Delta |
|---|---|
| Polling | Configurable via `PollIntervalDay/Night`, `DayStart/End`, `EnableUpload`, `SBFspotTimeoutSec`. Default 5 min day, no night polling (matches upstream). |
| Reliability | `timeout -s KILL` instead of `flock` for overlap protection — hung SBFspot runs die instead of blocking subsequent ticks ([ADR-001](../docs/ADR-001-timeout-over-flock.md)). |
| Observability | 4 MQTT-discovered diagnostic sensors: cron heartbeat, last status, hang counter, run duration ([ADR-003](../docs/ADR-003-heartbeat-architecture.md)). |
| Observability | Persistent daily logs in `/data/logs/` (bypasses supervisor's 100-line window). |
| Security | `chmod 600` on generated `SBFspot.cfg` (contains plaintext passwords). |
| UX | `Sensors_HA=Create` is one-shot; no more "remember to set back to No" foot-gun. |
| UX | No `!secret` references in option defaults; fresh installs work without `secrets.yaml`. |
| Bug fixes | `PVoutput_SID=""` no longer crashes cfg parse. `-d` flag removed from `mosquitto_pub` (was leaking MQTT password 288×/day to logs). |
| Build | `SBFspot` source pinned to tag `V3.9.12` (upstream cloned master without pin). |
| Publishing | Multi-arch images on `ghcr.io/maximv93/`, public, via GitHub Actions. |

## Heartbeat sensors

Once the addon runs with MQTT credentials, HA auto-discovers four sensors under the **HAOS-SBFspot (powerslider)** device:

- `sensor.haos_sbfspot_powerslider_sbfspot_cron_heartbeat` — last cron tick (any minute)
- `sensor.haos_sbfspot_powerslider_sbfspot_last_run_status` — `ok` / `hang` / `failed-N`
- `sensor.haos_sbfspot_powerslider_sbfspot_hang_count` — counter of timeout-killed runs
- `sensor.haos_sbfspot_powerslider_sbfspot_last_run_duration` — seconds

Use these in automations to alert on polling health. See [ADR-003](../docs/ADR-003-heartbeat-architecture.md) for the two-signal design.

## MariaDB + PVOutput (optional)

If you want archive-to-DB and PVOutput uploading:

1. Install and start the **MariaDB** addon.
2. Create database `sbfspot` + user `sbfspot` with a strong password.
3. Import the schema: [`CreateMySQLDB_no_drop.sql`](https://github.com/habuild/hassio-addons/blob/main/.images/CreateMySQLDB_no_drop.sql).
4. In this addon's config, set `SQL_Password`, leave hostname `core-mariadb`, port `3306`.
5. Set `PVoutput_SID` + `PVoutput_Key` with real values from pvoutput.org, or leave empty (fake stubs apply via our B1 fix).
6. Set `EnableUpload: true`.

For Home Assistant sensors without PVOutput, leave `EnableUpload: false` and skip the MariaDB steps.

## Links

- **Fork**: https://github.com/MaximV93/hassio-addons
- **Upstream**: https://github.com/habuild/hassio-addons (rebase source)
- **SBFspot core**: https://github.com/SBFspot/SBFspot
- **Addon docs**: [DOCS.md](./DOCS.md) — what's shown in the addon's Documentation tab
- **Troubleshooting**: [../docs/TROUBLESHOOTING.md](../docs/TROUBLESHOOTING.md)
- **Architecture decisions**: [../docs/ADR-*.md](../docs/)

## License

Apache 2.0. Same as upstream.

## Reporting issues

- **Fork bugs**: https://github.com/MaximV93/hassio-addons/issues
- **Upstream SBFspot bugs**: https://github.com/SBFspot/SBFspot/issues
