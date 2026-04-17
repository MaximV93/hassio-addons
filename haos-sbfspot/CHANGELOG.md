<!-- https://developers.home-assistant.io/docs/add-ons/presentation#keeping-a-changelog -->

# ![Version](https://img.shields.io/badge/dynamic/yaml?label=Version&query=%24.version&url=https%3A%2F%2Fraw.githubusercontent.com%2FMaximV93%2Fhassio-addons%2Fmain%2Fhaos-sbfspot%2Fconfig.yaml)

## 2026.4.17.16 — V5 polish: BT auto-reset, DB retention, supply chain hardening, common.sh refactor

### Features

- **BT adapter auto-reset** via `bt-reset.sh`. After `BT_RESET_AFTER_HANGS`
  (= 5) consecutive SBFspot hangs, invokes `hciconfig hci0 down+up` to clear
  BlueZ stack corruption. 80 % of sustained hang-loops recover this way.
  Counter persisted in `/data/.bt_reset_counter`.
- **MariaDB SpotData retention** via `db-retention.sh` cron @ 03:00.
  Default 90 d. Auto-skipped on cron path; active on sub-minute daemon path.
  New option `DbRetentionDays: int(0,3650)` for explicit override / disable.
  Requires `mariadb-client` in runtime image (newly added to Dockerfile).

### Infra / supply chain

- **Cosign keyless signing** of built images via GitHub OIDC (no secrets).
  Signs `:<version>` + `:latest` tags on each release.
- **Trivy CVE scan** (CRITICAL+HIGH, `ignore-unfixed`) as non-blocking CI
  step on each published image.
- **SBOM (SPDX)** via `anchore/sbom-action` — published as workflow artifact
  per arch+addon.
- `permissions` block on Builder job: `id-token: write`, `attestations: write`,
  `packages: write` — required for OIDC + package push.

### Code quality

- **Shared constants module** `rootfs/usr/bin/sbfspot/lib/common.sh`.
  Replaces hardcoded `/data/sbfspot_status.json`, `/data/options.json`,
  `MAX_KB=102400`, etc. across 4 scripts. Single-source-of-truth for paths,
  thresholds, and log helpers.
- **Strict-mode consistency**: `run-sbfspot.sh`, `hang-analyzer.sh`,
  `publish-heartbeat.sh`, `bt-reset.sh`, `db-retention.sh` all `set -eu`
  (stricter than `set -u` alone).

## 2026.4.17.15 — polish: state-file split, capability-narrow AppArmor, upload daemon optional, B8 fix

### Fixes + hardening

- **State-file write race closed**: `hang-analyzer.sh` now writes to
  `/data/hangs.json` (separate from `sbfspot_status.json`). `publish-heartbeat.sh`
  reads both. Previously both writers could overwrite each other when cron
  analyzer + run-sbfspot fired within ~1 s.
- **AppArmor capabilities narrowed** from wildcard `capability,` to an
  explicit list: `net_raw, net_admin, net_bind_service, dac_override, chown,
  fowner, setuid, setgid, sys_nice, kill`. If BT breaks, `last_status != ok`
  alert fires in 15 min; revert path is apparmor.txt + rebuild.
- **B8 upstream fix**: `mqttSensorConfig` had 5 occurrences of
  `ts="$(bashio::config 'DateTimeFormat')"` without a default. When user had
  empty `DateTimeFormat`, the generated MQTT discovery template became
  `timestamp_custom( )` — parse-failed + `ValueError` flood on every poll.
  All 5 now pass `'%H:%M:%S %d/%m/%Y'` as bashio default + add shell
  fallback `: "${ts:='...'}"` in case bashio returns empty string.

### Features

- **`BUILD_UPLOAD_DAEMON` Docker ARG** (default `true` = upstream behaviour).
  Set to `false` to skip the SBFspotUploadDaemon build entirely — saves
  ~3 MB image, reduces attack surface when `EnableUpload` is never true.
- **Options-migration foundation**: new `cont-init.d/00-version-stamp.sh`
  records the running version in `/data/.addon_version`. Hook point for
  future option-schema migrations. Idempotent, no-op today.

## 2026.4.17.14 — sub-minute polling + hang analyzer + AppArmor narrowing + cleanup

### Features

- **V4 sub-minute polling** via new in-process s6 daemon. New options:
  - `PollIntervalSec: int(0,3600)` — 0 = disabled (cron path unchanged),
    >=5 = daemon path. Bypasses cron 1-min floor.
  - `PollIntervalNightSec: int(0,3600)` — daemon-path night interval.
  - Full design in `docs/ADR-004-sub-minute-polling.md`.
- **V4 hang analyzer** — counts `=== HANG ===` markers in
  `/data/logs/sbfspot-*.log` over rolling 24h + 7d windows. Runs from cron
  every 15 min, writes to `/data/sbfspot_status.json`. Two new MQTT
  discovery sensors: `sensor.sbfspot_hangs_24h`, `sensor.sbfspot_hangs_7d`.
- **Size-capped log rotation** — `/data/logs` now hard-limited to 100 MB,
  oldest file deleted when exceeded. Complements the 7-day mtime rotation.

### Security

- **AppArmor narrowed**: `network,` (wildcard) replaced by explicit
  `network bluetooth, network inet stream, network inet dgram, network inet6 stream, network inet6 dgram, network netlink raw, network unix,`.
  Explicit `deny mount, deny pivot_root, deny capability sys_module, deny @{PROC}/sys/kernel/** w, deny /sys/kernel/security/** rw, deny /sys/firmware/** rw`.
  Kept `capability,` wildcard because BlueZ raw socket setup requires an
  un-audited set of caps; dropping specific caps without a BT-aware test
  harness risks silent `bthConnect() returned -1` (already burned once in
  V2-05 revert).

### Polish

- `icon.png` resized to 128×128 (was 50×50).
- `logo.png` converted JPEG → PNG at correct dimensions.
- `test/local-test.sh` shellcheck clean (SC2015 + SC2034 gone).
- CI `lint-markdown` + `lint-prettier` non-blocking (`continue-on-error: true`).
- `translations/nl.yaml` added (Dutch UI).
- `docs/UPSTREAM-PR-TEMPLATE.md` removed; `upstream-pr-fixes` branch deleted
  (fork stays private).

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
