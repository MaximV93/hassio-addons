#!/bin/sh
# powerslider fork V2-02: publish heartbeat MQTT discovery configs and/or
# current status to core-mosquitto. Runs from cron every tick.
#
# Publishes two sensors (HA auto-discovery):
#   - sensor.sbfspot_cron_heartbeat (timestamp, device_class timestamp)
#     → updates every cron tick regardless of SBFspot success/failure.
#       If this is fresh but sensor.haos_sbfspot_sma_timestamp is stale,
#       SBFspot is hanging or failing silently.
#   - sensor.sbfspot_last_status (string: ok|failed-<exit>|missing)
#     → reflects the last run-sbfspot.sh exit code via /data/sbfspot_status.json
set -u

STATUS=/data/sbfspot_status.json
MQTT_HOST=$(jq -r '.MQTT_Host // "core-mosquitto"' /data/options.json)
MQTT_PORT=$(jq -r '.MQTT_Port // "1883"' /data/options.json)
MQTT_USER=$(jq -r '.MQTT_User // ""' /data/options.json)
MQTT_PASS=$(jq -r '.MQTT_Pass // ""' /data/options.json)

if [ -z "${MQTT_USER}" ] || [ -z "${MQTT_PASS}" ]; then
    # No MQTT creds — silently skip. Addon may still be in setup phase.
    exit 0
fi

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

mqtt_pub() {
    topic="$1"
    msg="$2"
    /usr/bin/mosquitto_pub \
        -h "${MQTT_HOST}" -p "${MQTT_PORT}" \
        -u "${MQTT_USER}" -P "${MQTT_PASS}" \
        -t "${topic}" -m "${msg}" \
        --quiet 2>/dev/null || true
}

# Heartbeat value: current UTC timestamp
mqtt_pub "homeassistant/sbfspot/cron_heartbeat" "${NOW}"

# Status value: from status.json if available
if [ -f "${STATUS}" ] && command -v jq >/dev/null 2>&1; then
    STATUS_VALUE=$(jq -r '
        if .last_run_exit == null then "missing"
        elif .last_run_exit == 0 then "ok"
        else "failed-\(.last_run_exit)"
        end' "${STATUS}" 2>/dev/null || echo "missing")
else
    STATUS_VALUE="missing"
fi

mqtt_pub "homeassistant/sbfspot/last_status" "${STATUS_VALUE}"
