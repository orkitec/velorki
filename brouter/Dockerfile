# BRouter routing server for Velorki.
#
# WHY WE BUILD FROM SOURCE INSTEAD OF BASING ON AN OFFICIAL IMAGE:
#   Upstream (github.com/abrensch/brouter) publishes a Dockerfile and a
#   docs/developers/docker_guide.md, but it does NOT publish a prebuilt image.
#   There is no `abrensch/brouter` or `brouter/brouter` repository on Docker Hub
#   (both return 404) and no GHCR package. The docker guide only ever shows
#   `docker build -t brouter-<version> .` against a local checkout. So the only
#   reproducible option is to build the upstream repo ourselves at a pinned tag.
#
# WHY WE DO NOT USE UPSTREAM'S misc/scripts/standalone/server.sh:
#   That script *assigns* JAVA_OPTS unconditionally:
#       JAVA_OPTS="-Xmx128M -Xms128M -Xmn8M -DmaxRunningTime=300 ..."
#   so an externally supplied JAVA_OPTS (e.g. -Xmx512M from compose) is silently
#   discarded and the JVM stays capped at 128 MB. Our entrypoint.sh honours
#   JAVA_OPTS and launches the same main class with the same argument order.

ARG BROUTER_VERSION=v1.7.10

# ---------- build stage ----------
FROM gradle:jdk17-jammy AS build
ARG BROUTER_VERSION
RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /src
RUN git clone --depth 1 --branch "${BROUTER_VERSION}" \
      https://github.com/abrensch/brouter.git .
# Upstream ships CRLF line endings on gradlew; normalise before executing.
RUN sed -i 's/\r$//' gradlew && chmod +x gradlew
# -x test: the unit tests need extra fixtures and roughly double the build time;
# we only want the shaded server jar here.
RUN ./gradlew --no-daemon clean build -x test \
 && cp brouter-server/build/libs/brouter-*-all.jar /brouter.jar

# ---------- runtime stage ----------
FROM eclipse-temurin:17-jre-jammy
ARG BROUTER_VERSION
LABEL org.opencontainers.image.title="velorki-brouter" \
      org.opencontainers.image.source="https://github.com/abrensch/brouter" \
      org.opencontainers.image.version="${BROUTER_VERSION}" \
      org.opencontainers.image.licenses="MIT"

# wget is required by the compose healthcheck.
RUN apt-get update \
 && apt-get install -y --no-install-recommends wget ca-certificates \
 && rm -rf /var/lib/apt/lists/*

COPY --from=build /brouter.jar /app/brouter.jar
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh \
 && mkdir -p /segments4 /profiles2 /customprofiles \
 && useradd --system --uid 10001 --no-create-home brouter \
 && chown -R brouter:brouter /app /customprofiles

ENV JAVA_OPTS="-Xmx512M" \
    SEGMENTSPATH=/segments4 \
    PROFILESPATH=/profiles2 \
    CUSTOMPROFILESPATH=/customprofiles \
    BROUTER_PORT=17777 \
    BROUTER_MAXTHREADS=2 \
    MAX_RUNNING_TIME=300

USER brouter
EXPOSE 17777
ENTRYPOINT ["/app/entrypoint.sh"]
