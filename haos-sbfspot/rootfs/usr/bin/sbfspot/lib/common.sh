#!/bin/sh
# V5 polish: shared constants for powerslider fork scripts.
# Source this with: . /usr/bin/sbfspot/lib/common.sh
#
# Kept in /sh (POSIX) so it works for both `#!/bin/sh` and `#!/usr/bin/with-contenv bash`.
#
# shellcheck disable=SC2034 disable=SC2148
# (SC2034: vars sourced + used downstream; SC2148: sourced-only, shebang ignored)

# ---- filesystem paths ----
SBF_DIR=/usr/bin/sbfspot
SBF_BIN="${SBF_DIR}/SBFspot"
SBF_CFG="${SBF_DIR}/SBFspot.cfg"
SBF_UPLOAD_BIN="${SBF_DIR}/SBFspotUploadDaemon"
SBF_UPLOAD_CFG="${SBF_DIR}/SBFspotUpload.cfg"
RUN_WRAPPER="${SBF_DIR}/run-sbfspot.sh"

DATA_DIR=/data
LOG_DIR="${DATA_DIR}/logs"
STATUS_FILE="${DATA_DIR}/sbfspot_status.json"
HANGS_FILE="${DATA_DIR}/hangs.json"
OPTIONS_FILE="${DATA_DIR}/options.json"
VERSION_STAMP="${DATA_DIR}/.addon_version"
SENSORS_FLAG="${DATA_DIR}/.sensors_published"

# ---- limits + thresholds ----
LOG_MAX_KB=102400               # 100 MB size cap for /data/logs rotation
BT_RESET_AFTER_HANGS=5          # consecutive hangs before hciconfig reset
SBF_DAEMON_MIN_INTERVAL=5       # sub-minute daemon minimum interval (s)
SBF_DAEMON_MIN_TIMEOUT=40       # SBFspot needs >=40s for clean BT handshake
POLLER_CFG_WAIT_MAX=300         # max 5 min wait for SBFspot.cfg on startup

# ---- MQTT topic roots ----
MQTT_HEARTBEAT_ROOT="homeassistant/sbfspot"
MQTT_DISCOVERY_ROOT="homeassistant/sensor"

# ---- helpers ----
log_info() { echo "[$(basename "$0")] $*"; }
log_warn() { echo "[$(basename "$0")] WARN: $*" >&2; }
log_err()  { echo "[$(basename "$0")] ERROR: $*" >&2; }
