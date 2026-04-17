# powerslider fork — `habuild/hassio-addons`

This repository is a fork of [habuild/hassio-addons](https://github.com/habuild/hassio-addons) maintained by [MaximV93](https://github.com/MaximV93) (powerslider). Upstream work by HasQT / habuild community is preserved under `upstream/main`; our patches live on `main`.

Only the **`haos-sbfspot`** addon is actively modified. Sibling addons (`sbfspot`, `haos-sbfspot-sensorsgen`, `triinv-sbfspot`, `noip-renewer`) track upstream unchanged.

## Why a fork?

We run 2× SMA Sunny Boy HF-30 inverters (Bluetooth-only, no Speedwire) polled by SBFspot. Upstream had four issues that made production polling unreliable:

| # | Upstream issue | Our fix |
|---|---|---|
| B1 | `SBFspotUpload.cfg` parse error when `PVoutput_SID` is set to `""` (empty string) | Explicit shell fallback for empty-string case |
| B2 | `MQTT_PublisherArgs` contained `-d` debug flag → MQTT password printed to container log on every publish (~288×/day at 5-min poll) | Flag removed |
| B4 | `git clone https://github.com/sbfspot/SBFspot.git` without tag pin → rebuilds pulled whatever was on master | Pin to `V3.9.12` via `SBFSPOT_VERSION` build arg |
| polling | Hardcoded 5-min polling 6-22 h | Configurable via `PollIntervalDay/Night`, `DayStart/End` options |

We also added reliability + observability plumbing that makes hangs visible and recoverable:

| Area | Feature |
|---|---|
| Overlap | `timeout -s KILL` wraps every SBFspot call — hung runs die before the next tick instead of holding a lock |
| Logs | `/data/logs/sbfspot-YYYY-MM-DD.log` with 7-day rotation, bypasses supervisor's 100-line log window |
| Heartbeat | 4 MQTT-discovered HA sensors: `cron_heartbeat`, `last_run_status`, `hang_count`, `last_run_duration` |
| Config cleanup | No `!secret X` defaults (fresh install works without `secrets.yaml`) |
| Security | `chmod 600` on generated `SBFspot.cfg` (contains plaintext DB/MQTT/inverter passwords) |
| UX | `Sensors_HA=Create` is one-shot (won't re-publish on every restart) |

See [docs/](./docs/) for the full architectural decisions and [`haos-sbfspot/CHANGELOG.md`](./haos-sbfspot/CHANGELOG.md) for release notes.

## Installation

**Home Assistant Supervisor → Add-on Store → 3-dot menu → Repositories → Add**:

```
https://github.com/MaximV93/hassio-addons
```

Install **HAOS-SBFspot (powerslider)** from that repository. Configure via the addon UI. See [`haos-sbfspot/DOCS.md`](./haos-sbfspot/DOCS.md) for option reference.

Image is published at `ghcr.io/maximv93/{arch}-addon-haos-sbfspot`, public, no auth required.

## Image registry

GitHub Container Registry (`ghcr.io/maximv93/`) over Docker Hub because:

- No pull rate limits for anonymous users (Docker Hub: 100 pulls / 6 h / IP; triggers 429 on HA reinstall)
- Native integration with GitHub Actions via `GITHUB_TOKEN`
- Public images can be pulled without auth

Set once on fork setup:
1. Repository → Settings → Actions → General → Workflow permissions → Read and write
2. After first Builder run, make the container package public: https://github.com/users/MaximV93/packages/container/amd64-addon-haos-sbfspot/settings → Change visibility → Public

## Rebase from upstream

```sh
# Once
git remote add upstream https://github.com/habuild/hassio-addons.git

# Periodic rebase (reads latest upstream, replays our patches on top)
git fetch upstream
git rebase upstream/main

# If conflicts: resolve, `git rebase --continue`
# Force-push fork main (we're solo maintainer, no PR drama):
git push --force-with-lease origin main
```

Conflicts typically in `haos-sbfspot/config.yaml` (we modify options/schema), `haos-sbfspot/Dockerfile` (pin removed or changed), and `haos-sbfspot/rootfs/etc/services.d/sbfspot/run` (we added one-shot flag logic).

## Release flow

Every change to `haos-sbfspot/config.*` (monitored files in `.github/workflows/builder.yaml`) triggers a multi-arch Builder run that publishes to GHCR. Bump `version:` in `config.yaml` for a new release. Addons auto-update on the HA side once visible in the store.

```sh
# Typical loop
vim haos-sbfspot/...            # make the change
bash test/local-test.sh         # ~7s cached (shellcheck + hadolint + yamllint + docker build + smoke tests)
# bump version
sed -i 's/^version: .*/version: 2026.4.17.10/' haos-sbfspot/config.yaml
git add -A && git commit -m "haos-sbfspot X.Y.Z: <description>"
git push origin main            # triggers Builder
```

## License

Follows upstream: Apache 2.0. Patches contributed by powerslider remain under the same license.

## Questions?

Upstream: https://github.com/habuild/hassio-addons  
This fork: https://github.com/MaximV93/hassio-addons
