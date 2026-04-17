#!/bin/sh
# powerslider fork V2-04 + V2-02 + V5: wrapper for cron SBFspot invocations.
# - Duplicates output to both stdout (supervisor log, 100-line cap) and a
#   daily rotating file in /data/logs/ (persistent, 7-day retention + 100 MB).
# - Writes success/failure marker to /data/sbfspot_status.json for the
#   heartbeat publisher (V2-02) to surface via MQTT.
# - V5: triggers bt-reset.sh after BT_RESET_AFTER_HANGS consecutive hangs.
#
# Usage: run-sbfspot.sh <run-kind> <cmd...>
#   run-kind: short label (reboot|day|night|archive|discovery|daemon-day|...)
#   cmd:      SBFspot invocation (timeout ... SBFspot ...)
set -eu

. /usr/bin/sbfspot/lib/common.sh

KIND=${1:-unknown}
shift || true

STATUS="${STATUS_FILE}"
DATE=$(date +%Y-%m-%d)
LOG_FILE="${LOG_DIR}/sbfspot-${DATE}.log"

mkdir -p "${LOG_DIR}"
# Rotate: drop logs older than 7 days (silent if none)
find "${LOG_DIR}" -maxdepth 1 -type f -name 'sbfspot-*.log' -mtime +7 -delete 2>/dev/null || true

# V4 size-cap: at sub-minute polling the daily log grows fast (>10 MB/day).
# If total > LOG_MAX_KB, delete the oldest until we're under. Belt-and-braces
# safety net; 7-day time rotation is primary, this catches unexpected growth.
while :; do
    total_kb=$(du -sk "${LOG_DIR}" 2>/dev/null | awk '{print $1}')
    [ -z "${total_kb}" ] && break
    [ "${total_kb}" -le "${LOG_MAX_KB}" ] && break
    oldest=$(find "${LOG_DIR}" -maxdepth 1 -type f -name 'sbfspot-*.log' -printf '%T@ %p\n' 2>/dev/null | sort -n | head -1 | awk '{print $2}')
    [ -z "${oldest}" ] && break
    rm -f "${oldest}" || break
done

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

# V2-01: loud banner when run was killed by our timeout (exit 137 = SIGKILL from
# `timeout -s KILL`). Common cause: SBFspot hangs mid-session on marginal BT,
# or MIS-mode repeater read stalls for minutes. Workaround options:
#   - raise SBFspotTimeoutSec addon option
#   - lower BTConnectRetries (addon has it exposed, default 10, try 3)
#   - if consistent, place BT repeater closer to the marginal inverter
if [ "${RC}" = "137" ] || [ "${RC}" = "124" ]; then
    echo "=== [${END_TS}] ${KIND} HANG: killed after ${DURATION}s (exit ${RC})" | tee -a "${LOG_FILE}"
fi

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
        elif ($rc | tonumber) == 137 or ($rc | tonumber) == 124 then
            {last_failure_end: $ts, last_failure_kind: $kind, last_failure_exit: ($rc | tonumber),
             last_failure_reason: "hang-killed-by-timeout",
             hang_count: ((.hang_count // 0) + 1)}
        else {last_failure_end: $ts, last_failure_kind: $kind, last_failure_exit: ($rc | tonumber),
              last_failure_reason: "sbfspot-error"}
        end
    )' "${TMP}" > "${STATUS}.new" && mv "${STATUS}.new" "${STATUS}"
rm -f "${TMP}"

# V5: BT adapter reset after N consecutive hangs (hciconfig down+up)
/usr/bin/sbfspot/bt-reset.sh "${RC}" || true

# V5+ fixture capture: mirror daily log to /share/sbfspot-logs so SSH addon +
# Samba can read it. Idempotent; cp over existing.
if [ -d /share ] && [ -w /share ]; then
    mkdir -p /share/sbfspot-logs 2>/dev/null || true
    cp -f "${LOG_FILE}" /share/sbfspot-logs/ 2>/dev/null || true
fi

exit "${RC}"
