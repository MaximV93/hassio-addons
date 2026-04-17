#!/usr/bin/with-contenv bashio
# ==============================================================================
# Generate /etc/crontabs/root from addon options (powerslider fork).
# Runs once before services.d — standard HA addon cont-init.d pattern.
#
# Reads options directly via jq on /data/options.json (not bashio::config)
# because bashio::config requires a working Supervisor API and fails silently
# in off-HA environments (our local test harness). jq-direct is portable and
# produces identical results in production.
#
# Options consumed:
#   PollIntervalDay   (1-30, minutes)       default 5
#   PollIntervalNight (0-60, 0 = disabled)  default 0
#   DayStart          (0-23, hour)          default 6
#   DayEnd            (1-23, hour)          default 22
#   EnableUpload      (bool)                default true
#
# Every SBFspot invocation is wrapped in flock(1) on /run/sbfspot.lock to
# prevent overlapping BT sessions (B5 upstream bug).
# ==============================================================================
set -euo pipefail

readonly OPTIONS=/data/options.json

if [[ ! -f "${OPTIONS}" ]]; then
    bashio::log.fatal "Addon options file missing: ${OPTIONS}"
    exit 1
fi

# Read option with fallback when key is missing OR value is null.
# Usage: opt_or <key> <default>
#
# NOTE: jq's `//` operator treats `false` as "missing", which would wrongly
# substitute the default for a bool option set to false. We use an explicit
# null check so that `EnableUpload: false` survives intact.
opt_or() {
    local key="${1}" default="${2}"
    local value
    value=$(jq -r --arg k "${key}" 'if .[$k] == null then empty else .[$k] end' \
        "${OPTIONS}" 2>/dev/null || true)
    # Treat empty string (missing key) as "use default", but keep "false".
    if [[ -z "${value}" ]]; then
        printf '%s' "${default}"
    else
        printf '%s' "${value}"
    fi
}

# V5+ fixture capture: option-driven again now that .22 served its purpose.
# To re-enable capture, flip SBFspotDebug to 1-5 via addon UI (not via the
# config.yaml default — supervisor doesn't backfill existing options.json).
DEBUG_LEVEL=$(opt_or SBFspotDebug 0)
POLL_DAY=$(opt_or PollIntervalDay 5)
POLL_NIGHT=$(opt_or PollIntervalNight 0)
DAY_START=$(opt_or DayStart 6)
DAY_END=$(opt_or DayEnd 22)
ENABLE_UPLOAD=$(opt_or EnableUpload true)
# V2-03: 0 = auto (PollIntervalDay*60-10), else explicit override
SBF_TIMEOUT_OVERRIDE=$(opt_or SBFspotTimeoutSec 0)
# V4: sub-minute daemon polling. >= 5 activates the daemon at
# services.d/sbfspot-poller and SKIPS the day/night cron entries.
POLL_SEC=$(opt_or PollIntervalSec 0)

# Clamp to documented ranges defensively. Schema rejects out-of-range on save
# but treat this as belt-and-braces for migrations / malformed overrides.
(( POLL_DAY   < 1  )) && POLL_DAY=1
(( POLL_DAY   > 30 )) && POLL_DAY=30
(( POLL_NIGHT < 0  )) && POLL_NIGHT=0
(( POLL_NIGHT > 60 )) && POLL_NIGHT=60
(( DAY_START  < 0  )) && DAY_START=0
(( DAY_START  > 23 )) && DAY_START=23
(( DAY_END    < 1  )) && DAY_END=1
(( DAY_END    > 23 )) && DAY_END=23
if (( DAY_START >= DAY_END )); then
    bashio::log.warning "DayStart (${DAY_START}) >= DayEnd (${DAY_END}), forcing 6-22"
    DAY_START=6
    DAY_END=22
fi

readonly SBF=/usr/bin/sbfspot/SBFspot
# V5+ fixture capture: `-d#` (one letter + digit, no =) sets debug level 0-5.
# SBFspot V3.9.12 rejects -debug=5 syntax. `-finq` forces the inverter scan
# even when "it's dark" so hex dumps of the handshake phase are captured at
# night; spot data returns empty but the protocol exchange is still visible.
if (( DEBUG_LEVEL > 0 )); then
    SBF_DBG="-d${DEBUG_LEVEL} -finq"
else
    SBF_DBG=""
fi
readonly UPLOAD_DAEMON=/usr/bin/sbfspot/SBFspotUploadDaemon
readonly UPLOAD_CFG=/usr/bin/sbfspot/SBFspotUpload.cfg

# Overlap prevention: cap each SBFspot invocation at (POLL_DAY*60 - 10) seconds
# so it hard-kills before the next poll tick. Previous approach (`flock -n
# /run/sbfspot.lock`) turned out to silently block all subsequent runs when a
# single SBFspot call hung (observed 8+ min hangs after Logon OK). `timeout` is
# preferred: each tick has a fresh slate, no stale locks. Cost: overlap at the
# boundary if a run times out exactly as the next starts, but that's a one-off
# failed-run, self-healing at the next tick.
#
# BusyBox `timeout -s KILL <secs>` sends SIGKILL after the timeout. 10s buffer
# leaves time for BT-session cleanup before next tick fires.
# V2-03: user override vs auto-derived cap
if (( SBF_TIMEOUT_OVERRIDE > 0 )); then
    SBF_TIMEOUT=${SBF_TIMEOUT_OVERRIDE}
else
    SBF_TIMEOUT=$(( POLL_DAY * 60 - 10 ))
    (( SBF_TIMEOUT < 30 )) && SBF_TIMEOUT=30
fi
# V2-04: all SBFspot calls go through run-sbfspot.sh which: (1) dup output to
# /data/logs/sbfspot-YYYY-MM-DD.log with 7-day rotation, (2) write
# /data/sbfspot_status.json consumed by publish-heartbeat.sh (V2-02).
readonly RUN_WRAPPER=/usr/bin/sbfspot/run-sbfspot.sh

DAY_HOURS="${DAY_START}-${DAY_END}"

# Night window wraps midnight. Examples:
#   DayStart=6, DayEnd=22 → night = 23-23,0-5
#   DayStart=0, DayEnd=22 → night = 23-23
#   DayStart=6, DayEnd=23 → night = 0-5
#   DayStart=0, DayEnd=23 → no night window (no polling possible)
NIGHT_HOURS=""
if (( DAY_END < 23 )) && (( DAY_START > 0 )); then
    NIGHT_HOURS="$((DAY_END + 1))-23,0-$((DAY_START - 1))"
elif (( DAY_END < 23 )); then
    NIGHT_HOURS="$((DAY_END + 1))-23"
elif (( DAY_START > 0 )); then
    NIGHT_HOURS="0-$((DAY_START - 1))"
fi

{
    echo "SHELL=/bin/bash"
    echo "# Generated by 01-generate-crontab.sh — source of truth is addon options"
    echo ""
    echo "# V2-02 heartbeat: every minute, publishes timestamp + last-run status"
    echo "# to MQTT so HA can alert on staleness independent of SBFspot success."
    echo "* * * * *   /usr/bin/sbfspot/publish-heartbeat.sh"
    echo ""
    echo "# One-shot publish on container boot (ad0 = today only)"
    echo "@reboot sleep 30 && ${RUN_WRAPPER} reboot timeout -s KILL ${SBF_TIMEOUT} ${SBF} ${SBF_DBG} -v -ad0 -am0 -mqtt -finq"
    echo ""
    # V4: when PollIntervalSec is active, the sbfspot-poller s6 service runs the
    # day/night loop in-process. Skip the cron entries to avoid double-polling.
    if (( POLL_SEC >= 5 )); then
        echo "# Day/night cron poll entries SKIPPED — PollIntervalSec=${POLL_SEC}s"
        echo "# active; see services.d/sbfspot-poller/run."
    else
        echo "# Daytime polling: every ${POLL_DAY} min, hours ${DAY_HOURS}, timeout ${SBF_TIMEOUT}s"
        echo "*/${POLL_DAY} ${DAY_HOURS} * * *    ${RUN_WRAPPER} day timeout -s KILL ${SBF_TIMEOUT} ${SBF} ${SBF_DBG} -v -ad1 -am0 -ae0 -mqtt"

        if (( POLL_NIGHT > 0 )) && [[ -n "${NIGHT_HOURS}" ]]; then
            echo ""
            echo "# Nighttime polling: every ${POLL_NIGHT} min, hours ${NIGHT_HOURS}"
            NIGHT_TIMEOUT=$(( POLL_NIGHT * 60 - 10 ))
            (( NIGHT_TIMEOUT < 30 )) && NIGHT_TIMEOUT=30
            echo "*/${POLL_NIGHT} ${NIGHT_HOURS} * * *   ${RUN_WRAPPER} night timeout -s KILL ${NIGHT_TIMEOUT} ${SBF} ${SBF_DBG} -v -ad0 -am0 -mqtt"
        fi
    fi

    echo ""
    echo "# Daily archive poll at 05:55 (14-day catch-up, 5-min hard cap)"
    echo "55 05 * * *   ${RUN_WRAPPER} archive timeout -s KILL 300 ${SBF} ${SBF_DBG} -v -sp0 -ad14 -am1 -ae1 -mqtt -finq"

    if [[ "${ENABLE_UPLOAD,,}" == "true" ]]; then
        echo ""
        echo "# PVOutput uploader (background daemon, restarts on @reboot)"
        echo "@reboot sleep 60 && ${UPLOAD_DAEMON} -c ${UPLOAD_CFG} > /dev/stdout"
    fi

    echo ""
    echo "# Log tail heartbeat (keeps HA log visible during idle)"
    echo "*/${POLL_DAY} ${DAY_HOURS} * * *   /usr/bin/sbfspot/taillog.sh"

    echo ""
    echo "# V4 hang analyzer: count 'HANG' markers in daily logs → status.json."
    echo "# Runs every 15 min; publish-heartbeat.sh surfaces hangs_24h/hangs_7d."
    echo "*/15 * * * *    /usr/bin/sbfspot/hang-analyzer.sh"

    echo ""
    echo "# V5 DB retention: nightly SpotData cleanup. Opt-out via DbRetentionDays=0."
    echo "# Skipped entirely on cron path unless user overrides DbRetentionDays default."
    echo "0 3 * * *       /usr/bin/sbfspot/db-retention.sh"

    echo ""
    echo "# V5+ BT adapter health: hciconfig -a parsing + MQTT publish every 5 min."
    echo "# Correlate with hang_count to diagnose BT-stack root cause."
    echo "*/5 * * * *     /usr/bin/sbfspot/bt-health.sh"
} > /etc/crontabs/root

chmod 600 /etc/crontabs/root

bashio::log.info "Crontab generated:"
if (( POLL_SEC >= 5 )); then
    bashio::log.info "  daemon poll: every ${POLL_SEC}s (V4 daemon, cron day/night SKIPPED)"
else
    bashio::log.info "  day poll   : every ${POLL_DAY} min, hours ${DAY_HOURS}"
    if (( POLL_NIGHT > 0 )) && [[ -n "${NIGHT_HOURS}" ]]; then
        bashio::log.info "  night poll : every ${POLL_NIGHT} min, hours ${NIGHT_HOURS}"
    else
        bashio::log.info "  night poll : disabled"
    fi
fi
if [[ "${ENABLE_UPLOAD,,}" == "true" ]]; then
    bashio::log.info "  upload     : enabled"
else
    bashio::log.info "  upload     : disabled"
fi
if (( SBF_TIMEOUT_OVERRIDE > 0 )); then
    bashio::log.info "  SBFspot cap: ${SBF_TIMEOUT}s (explicit override), 300s (archive)"
else
    bashio::log.info "  SBFspot cap: ${SBF_TIMEOUT}s (auto = day_poll-10), 300s (archive)"
fi
