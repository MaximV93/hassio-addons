#!/bin/sh
# V5+ polish: parse hciconfig -a hci0 output for BT adapter health metrics,
# publish to MQTT for HA trending.
#
# Metrics exposed:
#   sbfspot_bt_rx_errors       — RX error counter (total since adapter up)
#   sbfspot_bt_tx_errors       — TX error counter
#   sbfspot_bt_rx_bytes        — cumulative RX bytes
#   sbfspot_bt_tx_bytes        — cumulative TX bytes
#   sbfspot_bt_uptime_seconds  — adapter uptime since last reset
#
# Rising error rates = interference, bad cable, failing dongle. Correlate with
# sbfspot_hang_count to identify BT-stack root cause.
#
# Runs from cron every 5 min. Cheap (hciconfig + awk).
set -eu

. /usr/bin/sbfspot/lib/common.sh

if ! command -v hciconfig >/dev/null 2>&1; then
    log_warn "bt-health: hciconfig not found, skipping"
    exit 0
fi

# hciconfig -a emits multi-line output like:
#   hci0:   Type: Primary  Bus: USB
#           ...
#           RX bytes:1234567 acl:0 sco:0 events:... errors:3
#           TX bytes:456789  acl:0 sco:0 commands:... errors:0
#           UP RUNNING PSCAN ISCAN
OUTPUT=$(hciconfig -a hci0 2>/dev/null || true)
if [ -z "${OUTPUT}" ]; then
    log_warn "bt-health: hciconfig -a hci0 empty (adapter not present?)"
    exit 0
fi

RX_BYTES=$(echo "${OUTPUT}" | awk '/RX bytes/{for(i=1;i<=NF;i++)if($i~/^bytes:/){gsub(/bytes:/,"",$i);print $i;exit}}')
RX_ERR=$(echo "${OUTPUT}" | awk '/RX bytes/{for(i=1;i<=NF;i++)if($i~/^errors:/){gsub(/errors:/,"",$i);print $i;exit}}')
TX_BYTES=$(echo "${OUTPUT}" | awk '/TX bytes/{for(i=1;i<=NF;i++)if($i~/^bytes:/){gsub(/bytes:/,"",$i);print $i;exit}}')
TX_ERR=$(echo "${OUTPUT}" | awk '/TX bytes/{for(i=1;i<=NF;i++)if($i~/^errors:/){gsub(/errors:/,"",$i);print $i;exit}}')

# Defaults if parsing fails
RX_BYTES=${RX_BYTES:-0}
RX_ERR=${RX_ERR:-0}
TX_BYTES=${TX_BYTES:-0}
TX_ERR=${TX_ERR:-0}

# MQTT credentials
MQTT_HOST=$(jq -r '.MQTT_Host // "core-mosquitto"' "${OPTIONS_FILE}" 2>/dev/null)
MQTT_PORT=$(jq -r '.MQTT_Port // "1883"' "${OPTIONS_FILE}" 2>/dev/null)
MQTT_USER=$(jq -r '.MQTT_User // ""' "${OPTIONS_FILE}" 2>/dev/null)
MQTT_PASS=$(jq -r '.MQTT_Pass // ""' "${OPTIONS_FILE}" 2>/dev/null)

if [ -z "${MQTT_USER}" ] || [ -z "${MQTT_PASS}" ]; then
    log_warn "bt-health: no MQTT creds, skipping publish"
    exit 0
fi

publish() {
    /usr/bin/mosquitto_pub \
        -h "${MQTT_HOST}" -p "${MQTT_PORT}" \
        -u "${MQTT_USER}" -P "${MQTT_PASS}" \
        -t "${MQTT_HEARTBEAT_ROOT}/$1" -m "$2" \
        --quiet 2>/dev/null || true
}

publish bt_rx_bytes "${RX_BYTES}"
publish bt_rx_errors "${RX_ERR}"
publish bt_tx_bytes "${TX_BYTES}"
publish bt_tx_errors "${TX_ERR}"
