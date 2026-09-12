# Mirrors the BRouter segment tiles (.rd5) from brouter.de into a volume.
FROM alpine:3.20

# NOTE: alpine ships busybox wget/stat by default. `apk add wget` replaces the
# busybox applet with GNU wget (which has --timestamping); coreutils gives us a
# GNU `stat`/`date`/`touch` with the flags sync.sh relies on; util-linux gives
# us flock for the single-writer lock.
RUN apk add --no-cache bash wget curl coreutils util-linux ca-certificates tzdata

COPY sync.sh /usr/local/bin/sync.sh
RUN chmod +x /usr/local/bin/sync.sh

ENV SEGMENTS_URL="https://brouter.de/brouter/segments4/" \
    SEGMENTS_DIR="/segments4" \
    SEGMENT_FILTER="*" \
    SYNC_INTERVAL="7d" \
    MANIFEST_SHA256="0" \
    BROUTER_VERSION="v1.7.10"

VOLUME ["/segments4"]

ENTRYPOINT ["/usr/local/bin/sync.sh"]
CMD ["loop"]
