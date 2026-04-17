ARG BUILD_FROM

# ───── build stage: rust:alpine compiles against musl to match runtime ────
# (Debian-based rust:slim produces glibc binaries that don't run on Alpine.)
FROM rust:1-alpine3.21 AS builder
RUN apk add --no-cache musl-dev git openssl-dev pkgconfig ca-certificates
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
