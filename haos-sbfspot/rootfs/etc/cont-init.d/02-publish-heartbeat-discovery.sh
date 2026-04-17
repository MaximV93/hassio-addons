#!/usr/bin/with-contenv bashio
# ==============================================================================
# V2-02: publish MQTT discovery configs for the heartbeat + status sensors.
# Runs once at addon start so HA auto-creates:
#   - sensor.sbfspot_cron_heartbeat (timestamp)
#   - sensor.sbfspot_last_status    (string: ok|failed-N|missing)
# Subsequent publishes happen via publish-heartbeat.sh on every cron tick.
# ==============================================================================
set -euo pipefail

readonly OPTIONS=/data/options.json

MQTT_HOST=$(jq -r '.MQTT_Host // "core-mosquitto"' "${OPTIONS}")
MQTT_PORT=$(jq -r '.MQTT_Port // "1883"' "${OPTIONS}")
MQTT_USER=$(jq -r '.MQTT_User // empty' "${OPTIONS}")
MQTT_PASS=$(jq -r '.MQTT_Pass // empty' "${OPTIONS}")

if [[ -z "${MQTT_USER}" || -z "${MQTT_PASS}" ]]; then
    bashio::log.warning "V2-02 heartbeat: MQTT credentials missing, skipping discovery publish"
    exit 0
fi

pub() {
    /usr/bin/mosquitto_pub \
        -h "${MQTT_HOST}" -p "${MQTT_PORT}" \
        -u "${MQTT_USER}" -P "${MQTT_PASS}" \
        -t "$1" -m "$2" --retain --quiet 2>/dev/null || true
}

# V3-03: `object_id` in each discovery config makes HA use it as the entity_id
# slug (becomes `sensor.sbfspot_cron_heartbeat`) instead of `device.name +
# unique_id` (`sensor.haos_sbfspot_powerslider_sbfspot_cron_heartbeat`).
#
# GOTCHA for upgraders: HA's entity registry is sticky by unique_id. Once an
# entity exists, adding `object_id` does NOT rename it — not even by publishing
# an empty payload to the discovery topic (HA preserves the entity_id across
# discovery removal + re-add). Fresh installs pick up object_id correctly.
# Upgraders must rename via Settings → Devices → MQTT → entity → edit ID, or
# via WebSocket `config/entity_registry/update {new_entity_id: ...}`. See
# docs/TROUBLESHOOTING.md "Stuck entity IDs after upgrade".
#
# Heartbeat timestamp sensor
pub "homeassistant/sensor/sbfspot_cron_heartbeat/config" '{
    "name": "SBFspot Cron Heartbeat",
    "object_id": "sbfspot_cron_heartbeat",
    "state_topic": "homeassistant/sbfspot/cron_heartbeat",
    "device_class": "timestamp",
    "unique_id": "sbfspot_cron_heartbeat",
    "entity_category": "diagnostic",
    "icon": "mdi:heart-pulse",
    "device": {
        "identifiers": ["sbfspot_addon"],
        "name": "HAOS-SBFspot (powerslider)",
        "manufacturer": "powerslider fork",
        "model": "haos-sbfspot"
    }
}'

# Last run status sensor (ok | hang | failed-N | missing)
pub "homeassistant/sensor/sbfspot_last_status/config" '{
    "name": "SBFspot Last Run Status",
    "object_id": "sbfspot_last_status",
    "state_topic": "homeassistant/sbfspot/last_status",
    "unique_id": "sbfspot_last_status",
    "entity_category": "diagnostic",
    "icon": "mdi:check-circle-outline",
    "device": {
        "identifiers": ["sbfspot_addon"],
        "name": "HAOS-SBFspot (powerslider)",
        "manufacturer": "powerslider fork",
        "model": "haos-sbfspot"
    }
}'

# V2-01: hang counter (total SIGKILL events from timeout wrapper)
pub "homeassistant/sensor/sbfspot_hang_count/config" '{
    "name": "SBFspot Hang Count",
    "object_id": "sbfspot_hang_count",
    "state_topic": "homeassistant/sbfspot/hang_count",
    "unique_id": "sbfspot_hang_count",
    "entity_category": "diagnostic",
    "state_class": "total_increasing",
    "icon": "mdi:alert-octagram-outline",
    "device": {
        "identifiers": ["sbfspot_addon"],
        "name": "HAOS-SBFspot (powerslider)",
        "manufacturer": "powerslider fork",
        "model": "haos-sbfspot"
    }
}'

# Last run duration (in seconds)
pub "homeassistant/sensor/sbfspot_last_duration/config" '{
    "name": "SBFspot Last Run Duration",
    "object_id": "sbfspot_last_duration",
    "state_topic": "homeassistant/sbfspot/last_duration",
    "unique_id": "sbfspot_last_duration",
    "entity_category": "diagnostic",
    "unit_of_measurement": "s",
    "state_class": "measurement",
    "icon": "mdi:timer-outline",
    "device": {
        "identifiers": ["sbfspot_addon"],
        "name": "HAOS-SBFspot (powerslider)",
        "manufacturer": "powerslider fork",
        "model": "haos-sbfspot"
    }
}'

# V4 hang-analyzer: 24h + 7d rolling counts from /data/logs/sbfspot-*.log
pub "homeassistant/sensor/sbfspot_hangs_24h/config" '{
    "name": "SBFspot Hangs 24h",
    "object_id": "sbfspot_hangs_24h",
    "state_topic": "homeassistant/sbfspot/hangs_24h",
    "unique_id": "sbfspot_hangs_24h",
    "entity_category": "diagnostic",
    "state_class": "measurement",
    "icon": "mdi:alert-decagram",
    "device": {
        "identifiers": ["sbfspot_addon"],
        "name": "HAOS-SBFspot (powerslider)",
        "manufacturer": "powerslider fork",
        "model": "haos-sbfspot"
    }
}'

pub "homeassistant/sensor/sbfspot_hangs_7d/config" '{
    "name": "SBFspot Hangs 7d",
    "object_id": "sbfspot_hangs_7d",
    "state_topic": "homeassistant/sbfspot/hangs_7d",
    "unique_id": "sbfspot_hangs_7d",
    "entity_category": "diagnostic",
    "state_class": "measurement",
    "icon": "mdi:alert-decagram-outline",
    "device": {
        "identifiers": ["sbfspot_addon"],
        "name": "HAOS-SBFspot (powerslider)",
        "manufacturer": "powerslider fork",
        "model": "haos-sbfspot"
    }
}'

bashio::log.info "V2-02+V4 heartbeat: MQTT discovery published (cron_heartbeat, last_status, hang_count, last_duration, hangs_24h, hangs_7d)"
