# MOTIS 2 for NYC with timetables prepared at build time.
# Build context: this directory (server/motis).

ARG ALPINE_VERSION=3.22

# Debian for the build stage: it packages osmium-tool, Alpine doesn't.
FROM debian:bookworm-slim AS build
ARG MOTIS_VERSION=v2.11.4
# Every download retries with exponential backoff (1, 2, 4, 8, 16 s), so one
# flaky host doesn't fail a build. Vercel and CI builders start without a
# layer cache, so each build fetches fresh feeds.
ENV CURL_RETRY="-fsSL --retry 5 --retry-all-errors --connect-timeout 30"
WORKDIR /srv/motis

RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends ca-certificates curl bzip2 osmium-tool > /dev/null \
 && rm -rf /var/lib/apt/lists/* \
 && curl $CURL_RETRY "https://github.com/motis-project/motis/releases/download/${MOTIS_VERSION}/motis-linux-amd64.tar.bz2" \
    | tar -xj ./motis \
 && ./motis --help > /dev/null

# OpenStreetMap: Geofabrik's New York State extract, clipped to the five
# boroughs. (BBBike's NYC extract timed out from GitHub and Vercel builders.)
RUN mkdir -p input \
 && curl $CURL_RETRY -o /tmp/ny.osm.pbf \
      https://download.geofabrik.de/north-america/us/new-york-latest.osm.pbf \
 && osmium extract --bbox=-74.28,40.48,-73.68,40.93 -o input/nyc.osm.pbf /tmp/ny.osm.pbf \
 && rm /tmp/ny.osm.pbf

# MTA GTFS: the supplemented subway feed (with SIR and planned work) and the
# six bus feeds.
RUN for feed in gtfs_supplemented gtfs_bx gtfs_b gtfs_m gtfs_q gtfs_si gtfs_busco; do \
      curl $CURL_RETRY -o "input/${feed}.zip" "https://rrgtfsfeeds.s3.amazonaws.com/${feed}.zip" || exit 1; \
    done

COPY config.yml ./
RUN ./motis import \
 && rm -rf data/logs \
 && mv data/config.yml config.server.yml

# Health check: serve the imported data and run the smoke test against it. A
# failure fails the build, so production keeps serving the previous image.
FROM build AS smoke
RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends bash jq > /dev/null \
 && rm -rf /var/lib/apt/lists/*
COPY smoke.sh smoke-build.sh ./
RUN bash smoke-build.sh && touch /smoke-passed

FROM alpine:${ALPINE_VERSION}
WORKDIR /srv/motis
# Depends on the smoke stage, so the build cannot skip it.
COPY --from=smoke /smoke-passed /srv/motis/smoke-passed
COPY --from=build /srv/motis/motis /usr/local/bin/motis
COPY --from=build /srv/motis/data data
COPY --from=build /srv/motis/config.server.yml ./
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
# The image filesystem may be read-only, so the config MOTIS reads lives in
# /tmp, written by the entrypoint with the port Vercel asks for.
RUN ln -s /tmp/motis-config.yml data/config.yml
ENV PORT=80
EXPOSE 80
ENTRYPOINT ["/bin/sh", "/usr/local/bin/entrypoint.sh"]
