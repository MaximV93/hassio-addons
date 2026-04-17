ARG BUILD_FROM

# ───── build stage: rust:1-slim gives us modern rustc + tools ─────────────
FROM rust:1-slim-bookworm AS builder
RUN apt-get update && apt-get install -y --no-install-recommends \
        git pkg-config libssl-dev ca-certificates && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /build

ARG HASS_SMA_RS_REF=master
RUN git clone --depth 50 --branch ${HASS_SMA_RS_REF} \
    https://github.com/MaximV93/hass-sma-rs.git /build
RUN cargo build --release --bin hass-sma-daemon && \
    strip target/release/hass-sma-daemon

# ───── runtime: HA Alpine base ─────────────────────────────────────────────
FROM $BUILD_FROM
RUN apk add --no-cache bluez bluez-libs
COPY --from=builder /build/target/release/hass-sma-daemon /usr/local/bin/hass-sma-daemon

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
