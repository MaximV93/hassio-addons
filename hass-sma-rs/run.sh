#!/usr/bin/with-contenv bashio
# Render /data/options.json into a YAML file the daemon consumes, then exec.
set -eu

OUT=/data/options.yaml

# The addon options JSON is already YAML-compatible as-is; pipe it through
# yq/jq-to-yaml only if there's drift. For now, just translate with a tiny
# Python one-liner to guarantee valid YAML output (dict of dicts + list).
python3 -c "
import json, sys, yaml
data = json.load(open('/data/options.json'))
open('${OUT}', 'w').write(yaml.safe_dump(data, sort_keys=False))
" 2>/dev/null || {
    # Fallback: the JSON IS valid YAML for our schema shape.
    cp /data/options.json "${OUT}"
}

bashio::log.info "hass-sma-rs starting with config:"
bashio::log.info "$(cat ${OUT})"

exec /usr/local/bin/hass-sma-daemon --config "${OUT}"
