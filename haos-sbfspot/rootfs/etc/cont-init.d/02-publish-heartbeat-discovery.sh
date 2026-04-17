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

# V3-03 migration (in 2026.4.17.12): HA MQTT discovery tracks entities by
# unique_id and does not rename existing entities when we add object_id.
# Publishing an empty payload to the discovery topic tells HA to remove the
# entity — then re-publishing the config creates a fresh entity respecting
# object_id. Idempotent on subsequent starts (old entity is already gone).
#
# One-time cost: automations/dashboards pointing at old entity_ids will break
# on first run of 2026.4.17.12+. Documented in CHANGELOG and DOCS.md.
migrate() {
    /usr/bin/mosquitto_pub \
        -h "${MQTT_HOST}" -p "${MQTT_PORT}" \
        -u "${MQTT_USER}" -P "${MQTT_PASS}" \
        -t "$1" -m "" --retain --quiet 2>/dev/null || true
}
migrate "homeassistant/sensor/sbfspot_cron_heartbeat/config"
migrate "homeassistant/sensor/sbfspot_last_status/config"
migrate "homeassistant/sensor/sbfspot_hang_count/config"
migrate "homeassistant/sensor/sbfspot_last_duration/config"
sleep 2

# V3-03: adding `object_id` to each discovery config forces HA to use it as
# entity_id instead of slug'ing device.name + unique_id. Without it, our sensors
# ended up as `sensor.haos_sbfspot_powerslider_sbfspot_cron_heartbeat`. With it,
# they become `sensor.sbfspot_cron_heartbeat` (cleaner, matches unique_id).
# NOTE: users upgrading past 2026.4.17.9 will see their existing long-named
# entities go stale (no updates). Repoint dashboards/automations to the new
# short names. The old entities become orphans and can be removed via Settings
# → Devices → MQTT → sbfspot_addon device (then orphans appear for deletion).
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

bashio::log.info "V2-02 heartbeat: MQTT discovery published (cron_heartbeat, last_status, hang_count, last_duration)"
