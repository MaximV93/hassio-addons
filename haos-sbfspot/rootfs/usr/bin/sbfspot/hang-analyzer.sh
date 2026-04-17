#!/bin/sh
# V4 hang analyzer: counts "=== HANG ===" markers in the daily sbfspot logs
# over two windows (24 h, 7 d) and writes them to /data/sbfspot_status.json.
# publish-heartbeat.sh reads status.json and publishes hangs_24h / hangs_7d
# to MQTT so HA can trend them (state_class: total over 24h/7d).
#
# Runs from cron every 15 min. Cheap (grep + wc on at most 7 log files).
set -u

LOG_DIR=/data/logs
STATUS=/data/sbfspot_status.json

command -v jq >/dev/null 2>&1 || exit 0
[ -d "${LOG_DIR}" ] || exit 0

NOW=$(date +%s)
CUTOFF_24H=$((NOW - 86400))
CUTOFF_7D=$((NOW - 7 * 86400))

count_recent() {
    # Count HANG markers across log files whose mtime is within $1 seconds.
    since_epoch=$1
    total=0
    for f in "${LOG_DIR}"/sbfspot-*.log; do
        [ -f "$f" ] || continue
        mtime=$(stat -c %Y "$f" 2>/dev/null || echo 0)
        [ "$mtime" -lt "$since_epoch" ] && continue
        n=$(grep -c "=== .* HANG:" "$f" 2>/dev/null || echo 0)
        total=$((total + n))
    done
    echo "$total"
}

H24=$(count_recent "${CUTOFF_24H}")
H7D=$(count_recent "${CUTOFF_7D}")

# Atomic merge into status.json
TMP=$(mktemp)
if [ -f "${STATUS}" ]; then
    cat "${STATUS}" > "${TMP}"
else
    echo '{}' > "${TMP}"
fi
jq --argjson h24 "${H24}" --argjson h7d "${H7D}" \
   '. + {hangs_24h: $h24, hangs_7d: $h7d, hangs_updated: now | todate}' \
   "${TMP}" > "${STATUS}.new" && mv "${STATUS}.new" "${STATUS}"
rm -f "${TMP}"
