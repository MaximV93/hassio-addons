<!-- https://developers.home-assistant.io/docs/add-ons/presentation#keeping-a-changelog -->

# ![Version](https://img.shields.io/badge/dynamic/yaml?label=Version&query=%24.version&url=https%3A%2F%2Fraw.githubusercontent.com%2FMaximV93%2Fhassio-addons%2Fmain%2Fhaos-sbfspot%2Fconfig.yaml)

## 2026.4.17.13 — migrate() removed, gotcha documented

- Discovered the `migrate()` empty-payload trick in 02-publish-heartbeat-discovery.sh
  does **not** rename existing entities. HA's entity registry preserves the
  `entity_id` across MQTT discovery removal + re-add when the `unique_id` is
  unchanged. `object_id` only applies to brand-new registry entries.
- Removed the misleading migrate() block. Fresh installs continue to pick up
  `object_id` correctly (no existing registry entry).
- Upgraders on this install: renamed 4 entities in-place via WebSocket
  `config/entity_registry/update` (see ADR-003 and docs/TROUBLESHOOTING.md).

## 2026.4.17 — powerslider fork v1

Fork of `habuild/hassio-addons/haos-sbfspot` with configurable polling and
upstream bug fixes. Published to `ghcr.io/maximv93/`.

### Features

- **Configurable poll interval** via addon options (no more hardcoded 5 min):
  - `PollIntervalDay` (1-30 min, default 5)
  - `PollIntervalNight` (0-60 min, default 0 = disabled)
  - `DayStart` / `DayEnd` (hour window, default 6-22)
  - `EnableUpload` (bool, default true — set false to skip SBFspotUploadDaemon)
- Runtime crontab generation via new `/etc/cont-init.d/01-generate-crontab.sh`
  (standard HA addon cont-init.d pattern). Replaces upstream's hardcoded
  `RUN echo` lines in Dockerfile.

### Bug fixes (upstream)

- **B1** — `PVoutput_SID=""` / `PVoutput_Key=""` no longer produces
  `SBFspotUpload.cfg` syntax error. Upstream relied on `bashio::config` default
  which doesn't apply to empty string values; we add an explicit shell fallback.
- **B2** — `MQTT_PublisherArgs` no longer carries `-d` debug flag that leaked
  the MQTT password to addon logs on every publish (was 288×/day at 5-min poll).
- **B4** — `SBFspot` source pinned to tag `V3.9.12` via `SBFSPOT_VERSION` build
  arg. Upstream ran `git clone` without pin → every rebuild pulled whatever
  was on master.
- **B5** — every SBFspot cron invocation wrapped in `flock -n
/run/sbfspot.lock`. Prevents overlapping BT sessions when the inverter takes
  > 1 poll interval to respond (critical at poll rates below 5 min).

### Infra

- Alpine package pins bumped to current 3.21 versions (upstream pins were
  stale → build broken upstream-only).
- `test/local-test.sh` for fast local iteration (shellcheck + hadolint +
  yamllint + docker build + smoke tests, ~7s cached).

### Not changed (intentional)

- `config.yaml` still uses `!secret` references as option defaults — matches
  upstream UX expectations. Can be overridden per install.
- `host_network: true`, `host_dbus: true` — needed for BlueZ BT access.
- `init: false` — upstream choice, s6-overlay direct.

### Backlog (v2)

See `MaximV93/hassio-addons` issue tracker tag `haos-sbfspot-v2`:

- chmod 600 on generated SBFspot.cfg (contains plaintext passwords)
- drop hardcoded day-window; rely on SBFspot's `SunRSOffset` for sunrise/sunset
- SBFspotUploadDaemon as s6 longrun (auto-restart on crash)
- Drop `!secret` defaults; UI-first flow

---

## Upstream changelog

- bump for SBFspot V3.9.12

## ![Release][release-shield-2025-1-0]

[release-shield-2025-1-0]: https://img.shields.io/badge/version-2025.1.0-blue.svg

- bump container base to 3.21
- bump dependencies for container base 3.21
- Add warning to docs about leave sensor creation set to NO until working MQTT connection.
- bug chasing on pi5 version.

## ![Release][release-shield-2024-7-1]

[release-shield-2024-7-1]: https://img.shields.io/badge/version-2024.7.1-blue.svg

- bump dependencies for container base 3.20
- added -mqtt to archive poll due to feature request

## ![Release][release-shield-2024-5-1]

[release-shield-2024-5-1]: https://img.shields.io/badge/version-2024.5.1-blue.svg

- Bump SPBspot to latest. Which is technically 3.9.9 due to SBFspot github setup.
- https://github.com/SBFspot/SBFspot/blob/master/SBFspot/version.h
- Bump base images to 3.19
- Bump dependencies

## ![Release][release-shield-2023-7-1]

[release-shield-2023-7-1]: https://img.shields.io/badge/version-2023.7.1-blue.svg

- Added network to apparmor capabilities for DEB12 supervised installs - issue75
- Added 14 day archive to daily archive function
- bump dependencies
- fixed some defunct nano config options

## ![Release][release-shield-2023-6-1]

[release-shield-2023-6-1]: https://img.shields.io/badge/version-2023.6.1-blue.svg

- Bump container base to 3.18
- Bump dependencies

## ![Release][release-shield-2023-1-1]

[release-shield-2023-1-1]: https://img.shields.io/badge/version-2023.1.1-blue.svg

- added share to container mapping
- bump for dependencies

## ![Release][release-shield-2022-11-1]

[release-shield-2022-11-1]: https://img.shields.io/badge/version-2022.11.1-blue.svg

- added MIS support to readme
- bump for dependencies
