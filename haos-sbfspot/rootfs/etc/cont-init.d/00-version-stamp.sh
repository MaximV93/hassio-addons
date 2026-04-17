#!/usr/bin/with-contenv bashio
# ==============================================================================
# V4 polish: stamp the running addon version into /data on every start.
# Foundation for future options-migration hooks.
#
# /data/.addon_version: last-known version that successfully booted.
# /data/.addon_version_new: version we're attempting to boot as.
#
# Migration hooks can compare the two (e.g. "if old < 2026.4.17.14 and new >=,
# rewrite obsolete options.json fields"). None needed today.
# ==============================================================================
set -euo pipefail

readonly STAMP=/data/.addon_version
readonly STAMP_NEW=/data/.addon_version_new

NEW_VERSION=$(jq -r '.version // "unknown"' /etc/s6-overlay/s6-rc.d/config.json 2>/dev/null || echo "unknown")
# config.json path isn't guaranteed — fall back to parsing config.yaml-ish.
if [[ "${NEW_VERSION}" == "unknown" ]]; then
    # Supervisor exposes the addon version via the 'SUPERVISOR_TOKEN' env only.
    # Fallback: grep our own config.yaml baked into the image.
    NEW_VERSION=$(grep -E '^version:' /config.yaml 2>/dev/null | awk '{print $2}' || echo "unknown")
fi

echo "${NEW_VERSION}" > "${STAMP_NEW}"

if [[ -f "${STAMP}" ]]; then
    OLD_VERSION=$(cat "${STAMP}" 2>/dev/null || echo "unknown")
    if [[ "${OLD_VERSION}" != "${NEW_VERSION}" ]]; then
        bashio::log.info "V4 stamp: upgrading from ${OLD_VERSION} to ${NEW_VERSION}"
        # Hook point: insert migration if needed
        # case "${OLD_VERSION}" in
        #     2026.4.17.13) ... ;;
        # esac
    fi
fi

# Only promote stamp on SUCCESSFUL boot — services.d/sbfspot will finalize
# this via a separate mechanism if needed. For now, write unconditionally.
mv "${STAMP_NEW}" "${STAMP}"

bashio::log.info "V4 stamp: addon version ${NEW_VERSION}"
