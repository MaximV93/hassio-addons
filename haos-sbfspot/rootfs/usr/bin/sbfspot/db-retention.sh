#!/bin/sh
# V5 polish: nightly SpotData retention. SBFspot writes one row per poll per
# inverter to `SpotData`. At 5-min polling = 210k rows/year (manageable).
# At 5-second polling = 12M rows/year → MariaDB bloat.
#
# Keeps SpotData for 90 days. DayData + MonthData + EventData are small and
# permanent. Runs nightly @ 03:00 via cron.
#
# Safe: DELETE uses LIMIT to avoid long table locks. Repeats until below row.
set -eu

. /usr/bin/sbfspot/lib/common.sh

# Enabled via addon option. Default: enabled only when PollIntervalSec >= 5 s
# (i.e. daemon mode → high row-count risk). Users on cron path untouched.
POLL_SEC=$(jq -r '.PollIntervalSec // 0' "${OPTIONS_FILE}" 2>/dev/null || echo 0)
DB_RETENTION_DAYS=$(jq -r '.DbRetentionDays // 90' "${OPTIONS_FILE}" 2>/dev/null || echo 90)

# Opt-out: DbRetentionDays=0 disables
if [ "${DB_RETENTION_DAYS}" = "0" ]; then
    log_info "DB retention disabled (DbRetentionDays=0)"
    exit 0
fi

# Opt-out: only active in daemon mode OR explicit DbRetentionDays>0
if [ "${POLL_SEC}" -lt 5 ] && [ "${DB_RETENTION_DAYS}" = "90" ]; then
    log_info "DB retention skipped (cron mode, default 90d not overridden)"
    exit 0
fi

DB_HOST=$(jq -r '.SQL_Hostname // "core-mariadb"' "${OPTIONS_FILE}")
DB_PORT=$(jq -r '.SQL_Port // "3306"' "${OPTIONS_FILE}")
DB_USER=$(jq -r '.SQL_Username // "sbfspot"' "${OPTIONS_FILE}")
DB_PASS=$(jq -r '.SQL_Password // ""' "${OPTIONS_FILE}")
DB_NAME=$(jq -r '.SQL_Database // "sbfspot"' "${OPTIONS_FILE}")

if [ -z "${DB_PASS}" ]; then
    log_warn "DB retention: no SQL_Password in options.json, skip"
    exit 0
fi

# MariaDB client ships in the base image via mariadb-connector-c.
# For DELETE we need mysql CLI, which is in mariadb-client (not installed).
# Fall back to a tiny Python one-liner with PyMySQL? Not installed either.
# Use mosquitto_pub-style approach: use mariadb-connector's mysqldump? No.
#
# Pragmatic: use the SBFspot binary itself — it links libmariadb. Skip DELETE
# via CLI and use a SBFspot flag? No such flag.
#
# Simplest shipping approach: ship a tiny `mysql` client. apk add
# mariadb-client is ~18 MB. Accept.
if ! command -v mysql >/dev/null 2>&1; then
    log_err "mysql CLI not installed; DB retention cannot run. Install mariadb-client in Dockerfile."
    exit 0
fi

cutoff_ts=$(date -d "-${DB_RETENTION_DAYS} days" '+%Y-%m-%d %H:%M:%S' 2>/dev/null \
           || date -v -"${DB_RETENTION_DAYS}"d '+%Y-%m-%d %H:%M:%S' 2>/dev/null \
           || echo '')

if [ -z "${cutoff_ts}" ]; then
    log_err "could not compute cutoff date"
    exit 1
fi

log_info "retention: deleting SpotData rows older than ${cutoff_ts}"

# Batch delete to avoid long locks. 10k rows per batch, loop until done.
total_deleted=0
while :; do
    affected=$(mysql -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" -p"${DB_PASS}" \
        "${DB_NAME}" -Nse "DELETE FROM SpotData WHERE TimeStamp < UNIX_TIMESTAMP('${cutoff_ts}') LIMIT 10000; SELECT ROW_COUNT();" 2>/dev/null || echo 0)
    [ "${affected}" = "0" ] && break
    total_deleted=$((total_deleted + affected))
    [ "${total_deleted}" -gt 1000000 ] && { log_warn "safety: deleted 1M rows; stopping batch"; break; }
done

log_info "retention: deleted ${total_deleted} SpotData rows"
