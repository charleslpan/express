# MOTIS 2 for NYC with timetables prepared at build time.
# Build context: this directory (server/motis).

ARG ALPINE_VERSION=3.22

# Debian for the build stage: it packages osmium-tool, Alpine doesn't.
FROM debian:bookworm-slim AS build
ARG MOTIS_VERSION=v2.11.4
WORKDIR /srv/motis

RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends ca-certificates curl bzip2 osmium-tool > /dev/null \
 && rm -rf /var/lib/apt/lists/* \
 && curl -fsSL "https://github.com/motis-project/motis/releases/download/${MOTIS_VERSION}/motis-linux-amd64.tar.bz2" \
    | tar -xj ./motis \
 && ./motis --help > /dev/null

# OpenStreetMap: Geofabrik's New York State extract, clipped to the five
# boroughs. (BBBike's NYC extract timed out from GitHub and Vercel builders.)
# The map changes slowly, so a cached layer is fine.
RUN mkdir -p input \
 && curl -fsSL --retry 3 --connect-timeout 30 -o /tmp/ny.osm.pbf \
      https://download.geofabrik.de/north-america/us/new-york-latest.osm.pbf \
 && osmium extract --bbox=-74.28,40.48,-73.68,40.93 -o input/nyc.osm.pbf /tmp/ny.osm.pbf \
 && rm /tmp/ny.osm.pbf

# ADD with a URL re-checks the remote file on every build, so a new feed
# busts the cache and the import below runs again.
ADD https://rrgtfsfeeds.s3.amazonaws.com/gtfs_supplemented.zip input/gtfs_supplemented.zip
ADD https://rrgtfsfeeds.s3.amazonaws.com/gtfs_bx.zip input/gtfs_bx.zip
ADD https://rrgtfsfeeds.s3.amazonaws.com/gtfs_b.zip input/gtfs_b.zip
ADD https://rrgtfsfeeds.s3.amazonaws.com/gtfs_m.zip input/gtfs_m.zip
ADD https://rrgtfsfeeds.s3.amazonaws.com/gtfs_q.zip input/gtfs_q.zip
ADD https://rrgtfsfeeds.s3.amazonaws.com/gtfs_si.zip input/gtfs_si.zip
ADD https://rrgtfsfeeds.s3.amazonaws.com/gtfs_busco.zip input/gtfs_busco.zip

COPY config.yml ./
RUN ./motis import \
 && rm -rf data/logs \
 && mv data/config.yml config.server.yml

FROM alpine:${ALPINE_VERSION}
WORKDIR /srv/motis
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
