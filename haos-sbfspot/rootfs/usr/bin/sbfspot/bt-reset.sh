#!/bin/sh
# V5 polish: reset the BT adapter when SBFspot has hung consecutively.
# Counts BT_RESET_AFTER_HANGS consecutive hangs via /data/sbfspot_status.json
# and invokes `hciconfig hci0 reset`. State persisted in /data/.bt_reset_count.
#
# Invoked by run-sbfspot.sh after writing status.json on a hang. Idempotent:
# safe to call after a success (clears counter).
set -eu

. /usr/bin/sbfspot/lib/common.sh

COUNTER="${DATA_DIR}/.bt_reset_counter"

last_rc="${1:-0}"

if [ "${last_rc}" = "137" ] || [ "${last_rc}" = "124" ]; then
    # Hang: increment counter
    count=$(cat "${COUNTER}" 2>/dev/null || echo 0)
    count=$((count + 1))
    echo "${count}" > "${COUNTER}"

    if [ "${count}" -ge "${BT_RESET_AFTER_HANGS}" ]; then
        log_info "BT reset triggered after ${count} consecutive hangs"
        # Prefer `hciconfig` if present (BlueZ 5.x), fall back to `bluetoothctl`.
        if command -v hciconfig >/dev/null 2>&1; then
            hciconfig hci0 down 2>&1 | sed 's/^/[bt-reset] /' || true
            sleep 1
            hciconfig hci0 up 2>&1 | sed 's/^/[bt-reset] /' || true
            log_info "hciconfig hci0 down+up complete"
        elif command -v bluetoothctl >/dev/null 2>&1; then
            bluetoothctl power off 2>&1 | sed 's/^/[bt-reset] /' || true
            sleep 1
            bluetoothctl power on 2>&1 | sed 's/^/[bt-reset] /' || true
            log_info "bluetoothctl power off+on complete"
        else
            log_warn "no hciconfig nor bluetoothctl found; cannot reset BT"
        fi
        # Reset counter after attempt (avoid loops)
        echo 0 > "${COUNTER}"
    fi
else
    # Success or non-hang failure: reset counter
    [ -f "${COUNTER}" ] && echo 0 > "${COUNTER}"
fi
