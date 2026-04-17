#!/usr/bin/env bash
# Local test harness — fast iteration outside HA supervisor.
# Runs: shellcheck + hadolint + yamllint + docker build + smoke tests
# Target: <2 min on amd64.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ADDON_DIR="$REPO_ROOT/haos-sbfspot"
TEST_IMAGE="sbfspot-test:local"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"

cd "$REPO_ROOT"

red()   { printf '\033[31m%s\033[0m\n' "$*" >&2; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
blue()  { printf '\033[36m%s\033[0m\n' "$*"; }

fail() { red "FAIL: $*"; exit 1; }
step() { blue "=== $* ==="; }

# ---- 1. shellcheck ----
run_shellcheck() {
  step "shellcheck"
  # bashio scripts start with `#!/usr/bin/with-contenv bashio` — shellcheck
  # parses them as bash (--shell=bash). `source` of bashio library is unreachable
  # during static analysis, so suppress SC1091. SC2155 (declare+assign) is noisy
  # on legacy scripts we don't own.
  local scripts=(
    "$ADDON_DIR/rootfs/etc/cont-init.d/01-generate-crontab.sh"
    "$ADDON_DIR/rootfs/etc/services.d/sbfspot/run"
    "$ADDON_DIR/rootfs/etc/services.d/sbfspot/finish"
    "$ADDON_DIR/rootfs/usr/bin/sbfspot/genBluetoothConfig.sh"
    "$ADDON_DIR/rootfs/usr/bin/sbfspot/genEthernetConfig.sh"
    "$ADDON_DIR/rootfs/usr/bin/sbfspot/taillog.sh"
  )
  local own=(
    "$ADDON_DIR/rootfs/etc/cont-init.d/01-generate-crontab.sh"
  )
  local rc=0
  # Strict on our own code
  for s in "${own[@]}"; do
    shellcheck --shell=bash --severity=warning --exclude=SC1091 "$s" || rc=1
  done
  # Legacy upstream code: info-level only (don't block on cosmetic issues)
  for s in "${scripts[@]}"; do
    [[ " ${own[*]} " == *" $s "* ]] && continue
    shellcheck --shell=bash --severity=error --exclude=SC1091,SC2155,SC2086,SC2046 "$s" || rc=1
  done
  [[ $rc -eq 0 ]] && green "  shellcheck OK" || fail "shellcheck failed"
}

# ---- 2. hadolint ----
run_hadolint() {
  step "hadolint"
  # Ignore: DL3008 (apt version pinning — N/A, we use apk), DL3018 (apk pin — already pinned).
  docker run --rm -i hadolint/hadolint:latest-alpine hadolint \
    --ignore DL3008 --ignore DL3018 - < "$ADDON_DIR/Dockerfile" \
    || fail "hadolint failed"
  green "  hadolint OK"
}

# ---- 3. yamllint ----
run_yamllint() {
  step "yamllint"
  yamllint -d '{extends: relaxed, rules: {line-length: disable, indentation: disable, trailing-spaces: disable, empty-lines: disable}}' \
    "$ADDON_DIR/config.yaml" "$ADDON_DIR/build.yaml" \
    || fail "yamllint failed"
  green "  yamllint OK"
}

# ---- 4. docker build ----
run_docker_build() {
  step "docker build (amd64, ~5 min first time, ~30s cached)"
  local tempio_version build_from
  tempio_version=$(awk -F'"' '/TEMPIO_VERSION:/{print $2}' "$ADDON_DIR/build.yaml")
  build_from=$(awk -F'"' '/amd64:/{print $2}' "$ADDON_DIR/build.yaml")
  [[ -z "$tempio_version" ]] && fail "could not parse TEMPIO_VERSION from build.yaml"
  [[ -z "$build_from"    ]] && fail "could not parse amd64 base from build.yaml"

  docker build \
    --build-arg BUILD_FROM="$build_from" \
    --build-arg TEMPIO_VERSION="$tempio_version" \
    --build-arg BUILD_ARCH=amd64 \
    -t "$TEST_IMAGE" \
    "$ADDON_DIR" >/tmp/sbfspot-build.log 2>&1 \
    || { tail -40 /tmp/sbfspot-build.log; fail "docker build failed (log: /tmp/sbfspot-build.log)"; }
  green "  docker build OK"
}

# ---- 5. smoke tests ----
run_smoke() {
  local fixture="$1"
  local name
  name=$(basename "$fixture" .json)
  step "smoke: $name"

  local out
  out=$(timeout 30 docker run --rm \
    -v "$fixture:/data/options.json:ro" \
    --entrypoint bash "$TEST_IMAGE" \
    -c '
      set -eo pipefail
      # s6-overlay env dir must exist for with-contenv shebangs (bashio scripts).
      # Normally populated by s6 init; we stub it here so tests can run without init.
      mkdir -p /run/s6/container_environment
      # Generate crontab from options via our cont-init.d script
      /etc/cont-init.d/01-generate-crontab.sh 2>&1
      # Generate SBFspot.cfg + SBFspotUpload.cfg via Bluetooth gen script
      # (bashio::config inside will log Supervisor API errors — ignore, fallback
      # defaults apply)
      /usr/bin/sbfspot/genBluetoothConfig.sh /tmp/SBFspot.cfg /tmp/SBFspotUpload.cfg 2>&1 || true
      echo "--- CRONTAB ---"
      cat /etc/crontabs/root
      echo "--- SBFSPOT.CFG ---"
      grep -E "^(BTAddress|Password|Plantname|MIS_Enabled|MQTT_PublisherArgs|SQL_Password)=" /tmp/SBFspot.cfg || echo "(missing)"
      echo "--- UPLOAD.CFG (PVoutput) ---"
      grep -E "^PVoutput_" /tmp/SBFspotUpload.cfg || echo "(missing)"
    ' 2>&1)

  echo "$out"

  assert_match() { grep -qE "$1" <<<"$out" || fail "[$name] expected pattern: $1"; }
  assert_no_match() { ! grep -qE "$1" <<<"$out" || fail "[$name] unexpected pattern: $1"; }

  # Shared assertions — regression tests for upstream bugs we fixed.
  # Note: BTAddress/Password/etc. come from bashio::config which requires a
  # live Supervisor API, so those values appear empty in local tests. That's
  # expected; the real verification happens in the HA smoke test.
  assert_no_match '^PVoutput_SID=$'              # B1: fallback kicks in
  assert_no_match '^PVoutput_Key=$'              # B1: fallback kicks in
  assert_match '^PVoutput_SID=[0-9]'             # B1: got default
  # B2: no trailing -d flag on the PublisherArgs line (used to leak pw)
  assert_no_match 'PublisherArgs=.* -d *$'

  # Fixture-specific crontab assertions (our cont-init.d is jq-direct and works)
  case "$name" in
    options.default)
      assert_match 'timeout -s KILL 50'            # PollIntervalDay=1 → 60-10=50s
      assert_match '\*/1 6-22 \* \* \*'
      assert_match '\*/15 23-23,0-5 \* \* \*'
      assert_match 'SBFspotUploadDaemon'           # upload enabled
      ;;
    options.minimal)
      assert_match 'timeout -s KILL 290'           # default PollIntervalDay=5 → 300-10=290s
      assert_match '\*/5 6-22'
      assert_no_match 'Nighttime polling'
      ;;
    options.night-off)
      assert_match '\*/5 6-22'
      assert_no_match 'Nighttime polling'
      assert_no_match 'SBFspotUploadDaemon'
      ;;
  esac
  green "  smoke $name OK"
}

main() {
  local start=$SECONDS
  run_shellcheck
  run_hadolint
  run_yamllint
  run_docker_build
  for fixture in "$FIXTURES_DIR"/options.*.json; do
    run_smoke "$fixture"
  done
  green "=== ALL TESTS PASSED (${SECONDS}s since start, build in /tmp/sbfspot-build.log) ==="
}

main "$@"
