#!/bin/sh
# powerslider fork V2-04 + V2-02: wrapper for cron SBFspot invocations.
# - Duplicates output to both stdout (supervisor log, 100-line cap) and a
#   daily rotating file in /data/logs/ (persistent, 7-day retention).
# - Writes success/failure marker to /data/sbfspot_status.json for the
#   heartbeat publisher (V2-02) to surface via MQTT.
#
# Usage: run-sbfspot.sh <run-kind> <cmd...>
#   run-kind: short label (reboot|day|night|archive|discovery)
#   cmd:      SBFspot invocation (timeout ... SBFspot ...)
set -u

KIND=${1:-unknown}
shift || true

LOG_DIR=/data/logs
STATUS=/data/sbfspot_status.json
DATE=$(date +%Y-%m-%d)
LOG_FILE="${LOG_DIR}/sbfspot-${DATE}.log"

mkdir -p "${LOG_DIR}"
# Rotate: drop logs older than 7 days (silent if none)
find "${LOG_DIR}" -maxdepth 1 -type f -name 'sbfspot-*.log' -mtime +7 -delete 2>/dev/null || true

START_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
START_EPOCH=$(date +%s)
RC_FILE=$(mktemp)

# Run + tee. Subshell captures real exit code (POSIX-portable alternative to
# PIPESTATUS which busybox sh lacks).
{
    echo "=== [${START_TS}] ${KIND} run: $* ==="
    "$@"
    echo $? > "${RC_FILE}"
} 2>&1 | tee -a "${LOG_FILE}"

RC=$(cat "${RC_FILE}" 2>/dev/null || echo 255)
rm -f "${RC_FILE}"

END_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
DURATION=$(( $(date +%s) - START_EPOCH ))

# Atomic status.json update via jq merge
TMP=$(mktemp)
if [ -f "${STATUS}" ]; then
    cat "${STATUS}" > "${TMP}"
else
    echo '{}' > "${TMP}"
fi

jq --arg kind "${KIND}" \
   --arg ts "${END_TS}" \
   --arg rc "${RC}" \
   --arg dur "${DURATION}" \
   '. + {
        last_run_kind: $kind,
        last_run_end: $ts,
        last_run_exit: ($rc | tonumber),
        last_run_duration_sec: ($dur | tonumber),
    } + (
        if ($rc | tonumber) == 0 then {last_success_end: $ts, last_success_kind: $kind}
        else {last_failure_end: $ts, last_failure_kind: $kind, last_failure_exit: ($rc | tonumber)}
        end
    )' "${TMP}" > "${STATUS}.new" && mv "${STATUS}.new" "${STATUS}"
rm -f "${TMP}"

exit "${RC}"
