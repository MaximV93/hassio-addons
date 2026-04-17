ARG BUILD_FROM
# Use the HA base image only at RUNTIME. The Rust build needs a modern rustc
# (>=1.75), which the HA base images lack — we do the compile in a separate
# stage using rust:1-slim-bookworm.
#
# Security note: the runtime stage keeps the HA base image because it ships
# bluez + s6 + bashio, which we need for BT.

# ───── build stage ─────────────────────────────────────────────────────────
FROM rust:1-slim-bookworm AS builder
RUN apt-get update && apt-get install -y --no-install-recommends \
        pkg-config libssl-dev && rm -rf /var/lib/apt/lists/*
WORKDIR /build

# The hass-sma-rs source lives in a separate public repo. Clone a pinned
# commit at build time rather than vendoring it into this repo (keeps the
# addon manifest small; the pinned SHA is auditable).
ARG HASS_SMA_RS_REF=master
RUN git clone --depth 100 https://github.com/MaximV93/hass-sma-rs.git /build && \
    git checkout ${HASS_SMA_RS_REF}
RUN cargo build --release --bin hass-sma-daemon
RUN strip target/release/hass-sma-daemon

# ───── runtime stage ──────────────────────────────────────────────────────
FROM $BUILD_FROM
RUN apk add --no-cache bluez=5.79-r0 bluez-libs=5.79-r0 python3=3.12.12-r0 py3-yaml=6.0.2-r3
COPY --from=builder /build/target/release/hass-sma-daemon /usr/local/bin/hass-sma-daemon

# Rendered from options.json by run.sh before entrypoint.
COPY run.sh /run.sh
RUN chmod a+x /run.sh

CMD ["/run.sh"]

LABEL \
    io.hass.name="hass-sma-rs (Rust rewrite)" \
    io.hass.description="Clean-room Rust daemon for SMA Sunny Boy BT inverters" \
    io.hass.arch="${BUILD_ARCH}" \
    io.hass.type="addon" \
    io.hass.version=${BUILD_VERSION} \
    maintainer="Maxim Vandebroeck"
