#!/usr/bin/with-contenv bashio
# /data/options.json IS valid YAML for our schema shape (dict of dicts + list
# of dicts), so pass it straight to the daemon.
set -eu

bashio::log.info "hass-sma-rs starting"
bashio::log.info "config: $(cat /data/options.json)"

# Verbose protocol logs during this bring-up phase; reduce once stable.
export RUST_LOG="${RUST_LOG:-debug,rumqttc=info,hyper=info,sqlx=info}"
export RUST_BACKTRACE=1

exec /usr/local/bin/hass-sma-daemon --config /data/options.json
