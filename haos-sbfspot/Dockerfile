## https://developers.home-assistant.io/docs/add-ons/configuration#add-on-dockerfile
ARG BUILD_FROM
FROM $BUILD_FROM AS builder-base

# Execute during the build of the image
ARG TEMPIO_VERSION BUILD_ARCH
# powerslider fork: pin SBFspot to a released tag (B4). Upstream had no pin;
# every rebuild pulled whatever was on master. Override via --build-arg.
ARG SBFSPOT_VERSION=V3.9.12
# V4 polish: optionally skip SBFspotUploadDaemon build. Default keeps upstream
# behaviour (built + shipped). Set to false to save ~3 MB image + reduce
# attack surface when EnableUpload is never going to be true.
ARG BUILD_UPLOAD_DAEMON=true
RUN \
    curl -sSLf -o /usr/bin/tempio \
    "https://github.com/home-assistant/tempio/releases/download/${TEMPIO_VERSION}/tempio_${BUILD_ARCH}"

# Copy root filesystem
COPY rootfs /
# Set shell
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# install requirements
RUN apk update && apk add --no-cache \
    bluez=5.79-r0 \
    bluez-dev=5.79-r0 \
    boost-dev=1.84.0-r2 \
    curl-dev=8.14.1-r2 \
    git=2.47.3-r0 \
    g++=14.2.0-r4 \
    make=4.4.1-r2 \
    mariadb-dev=11.4.8-r0 \
    mosquitto-clients=2.0.20-r0 \
    tzdata=2026a-r0

# download and build SBFspot — pinned for reproducibility
WORKDIR /tmp
RUN \
    git clone --depth 1 --branch "${SBFSPOT_VERSION}" https://github.com/sbfspot/SBFspot.git . \
    && sed -i s/mariadbclient/mariadb/ ./SBFspot/makefile \
    && make -C ./SBFspot mariadb \
    && if [ "${BUILD_UPLOAD_DAEMON}" = "true" ]; then \
           sed -i s/mariadbclient/mariadb/ ./SBFspotUploadDaemon/makefile \
           && make -C ./SBFspotUploadDaemon mariadb ; \
       else \
           echo "V4: SBFspotUploadDaemon build skipped (BUILD_UPLOAD_DAEMON=false)" ; \
           mkdir -p /tmp/SBFspotUploadDaemon/mariadb/bin ; \
           : > /tmp/SBFspotUploadDaemon/mariadb/bin/SBFspotUploadDaemon ; \
       fi


# runtinme container   
FROM $BUILD_FROM

ARG TEMPIO_VERSION BUILD_ARCH
RUN \
    curl -sSLf -o /usr/bin/tempio \
    "https://github.com/home-assistant/tempio/releases/download/${TEMPIO_VERSION}/tempio_${BUILD_ARCH}"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]


RUN apk update && apk add --no-cache \
    bluez=5.79-r0 \
    bluez-libs=5.79-r0 \
    nano=8.2-r0 \
    libstdc++=14.2.0-r4 \
    mariadb-client=11.4.8-r0 \
    mariadb-common=11.4.8-r0 \
    mariadb-connector-c=3.3.10-r0 \
    ncurses-libs=6.5_p20241006-r3 \
    libcurl=8.14.1-r2 \
    mosquitto-clients=2.0.20-r0
    
    #tzdata=2023c-r1 
    #boost-date_time1.78 



# Copy data for add-on
WORKDIR /usr/bin/sbfspot

COPY --from=builder-base /tmp/SBFspot/mariadb/bin/SBFspot /usr/bin/sbfspot/SBFspot
COPY --from=builder-base /tmp/SBFspotUploadDaemon/mariadb/bin/SBFspotUploadDaemon /usr/bin/sbfspot/SBFspotUploadDaemon
COPY --from=builder-base /tmp/SBFspot/date_time_zonespec.csv /usr/bin/sbfspot/date_time_zonespec.csv
COPY --from=builder-base /tmp/SBFspot/TagList* /usr/bin/sbfspot/



#RUN cp /tmp/SBFspot/mariadb/bin/SBFspot /usr/bin/sbfspot \
# && cp /tmp/SBFspotUploadDaemon/mariadb/bin/SBFspotUploadDaemon /usr/bin/sbfspot \
# && cp /tmp/SBFspot/date_time_zonespec.csv /usr/bin/sbfspot \
# && cp /tmp/SBFspot/TagList* /usr/bin/sbfspot

COPY rootfs /

RUN chmod a+x /etc/services.d/sbfspot/** /etc/services.d/sbfspot-poller/** /etc/cont-init.d/** /usr/bin/sbfspot/*.sh /usr/bin/sbfspot/lib/*.sh

# powerslider fork: crontab is generated at runtime by
# /etc/cont-init.d/01-generate-crontab.sh from addon options
# (PollIntervalDay / PollIntervalNight / DayStart / DayEnd / EnableUpload).
# Upstream's hardcoded RUN echo lines removed.

# Labels
LABEL \
    io.hass.name="HAOS-SBFspot" \
    io.hass.description="Home Assistant addon for Bluetooth SBFspot, is an open source project to get actual and archive data out of an SMA® inverter over Bluetooth or Ethernet (Speedwire®)" \
    io.hass.arch="${BUILD_ARCH}" \
    io.hass.type="addon" \
    io.hass.version=${BUILD_VERSION} \
    maintainer="Hasqt <https://community.home-assistant.io/u/hasqt>" \
    org.label-schema.description="Home Assistant addon for Bluetooth SBFspot, is an open source project to get actual and archive data out of an SMA® inverter over Bluetooth or Ethernet (Speedwire®)" \
    org.label-schema.build-date=${BUILD_DATE} \
    org.label-schema.name="HAOS-SBFspot" \
    org.label-schema.schema-version="1.0" \
    org.label-schema.url="https://github.com/MaximV93/hassio-addons/tree/main/haos-sbfspot" \
    org.label-schema.usage="https://github.com/MaximV93/hassio-addons/tree/main/haos-sbfspot/README.md" \
    org.label-schema.vcs-ref=${BUILD_REF} \
    org.label-schema.vcs-url="https://github.com/MaximV93/hassio-addons" \
    org.label-schema.vendor="powerslider"


#Launch nginx with debug options. not working yet
#CMD [ "nginx","-g","daemon off;error_log /dev/stdout debug;" ] 
