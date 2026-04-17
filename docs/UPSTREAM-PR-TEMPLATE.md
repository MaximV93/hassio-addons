# Upstream PR template (not yet submitted)

Branch `upstream-pr-fixes` contains 2 cleanly-cherry-picked commits on top of upstream `habuild/hassio-addons/main`. They are self-contained, upstream-friendly, and zero behavioural change for existing users.

## Commits on the branch

1. **`haos-sbfspot: fix PVoutput empty-string cfg parse error + drop mosquitto_pub -d flag`**  
   Bug fix + security fix. No option schema changes.

2. **`haos-sbfspot: pin SBFspot source + refresh Alpine 3.21 package pins`**  
   Build reproducibility. Upstream's build is currently broken (pins moved), so this restores it to working state + adds a `SBFSPOT_VERSION` override.

## How to submit (when ready)

```sh
gh pr create \
    --repo habuild/hassio-addons \
    --base main \
    --head MaximV93:upstream-pr-fixes \
    --title "haos-sbfspot: bug fixes + Alpine pin refresh + SBFspot source pin" \
    --body "$(cat docs/UPSTREAM-PR-BODY.md)"
```

## PR body (paste into the GitHub PR form)

```md
Hi habuild community 👋

This PR collects four small improvements to `haos-sbfspot` that I hit while productionising the addon on a 2-inverter setup. Each commit is self-contained and individually revertible; happy to split if you prefer separate PRs.

### 1. `PVoutput_SID=""` no longer breaks `SBFspotUpload.cfg`

`bashio::config 'key' 'default'` only applies the default when the key is
missing from `options.json` — not when the user set it to empty. Users
who don't run PVOutput naturally set it to `""`, which produces
`PVoutput_SID=` in the generated cfg and makes SBFspotUploadDaemon error
with `Configuration Error: Syntax error on line 34`.

Fixed with an explicit shell fallback in both gen scripts (Bluetooth and
Ethernet paths).

### 2. Drop `-d` flag from `MQTT_PublisherArgs`

The `-d` flag puts `mosquitto_pub` in debug mode. Result: every publish
prints connection details + topic + message to the supervisor log, and
the `-P <password>` argv is visible in `ps aux` inside the container.
At 5-min polling that's 288× password exposure per day. Remove `-d`;
users who want MQTT debug can run `mosquitto_pub -d` by hand.

### 3. Pin `SBFspot` clone to a tag

`git clone https://github.com/sbfspot/SBFspot.git .` without a branch
was pulling master at build time. Non-reproducible, silent-break risk
on upstream changes. Now: `--depth 1 --branch V3.9.12` with
`SBFSPOT_VERSION` build arg for future bumps.

### 4. Refresh Alpine 3.21 pins (build is currently broken)

Alpine repo moved past the pinned versions (`curl-dev`, `git`,
`mariadb-dev`, `tzdata`, `libcurl`, `mariadb-common`). `apk add` fails
with `unable to select packages`. Bumped to the current Alpine 3.21
versions. Both builder and runtime stages.

### Testing

Built locally for amd64 + ran against 2× SMA Sunny Boy HF-30 inverters
over BT (MIS mode). Normal polling, data publishing, and MQTT discovery
all confirmed working. The `-d` removal doesn't change anything user-
visible except a quieter log.

### Why now

Build has been broken for anyone who wanted to rebuild from source
(locally, without using the published ghcr.io image) since Alpine
pushed updated packages. The Alpine bump alone is the urgent fix —
the other three are "while I'm in there" quality improvements.

Happy to iterate if the shape doesn't fit the project's style. Thanks
for the solid addon foundation!
```

## Before submitting

- [ ] Rebase against current `upstream/main` to resolve conflicts (`git fetch upstream && git rebase upstream/main`)
- [ ] Run the fork's local tests (`bash test/local-test.sh`)
- [ ] Check upstream CI passes on the PR (addon-linter, shellcheck, hadolint, yamllint)
- [ ] Wait a day — let any 11th-hour review of the 4 commits happen

## If the PR is closed without merging

Keep the branch on our fork; it's a reference for our next upstream attempt. Our `main` branch keeps the same fixes integrated (and more) — no loss.
