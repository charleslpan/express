# MOTIS 2 for NYC with timetables prepared at build time.
# Build context: this directory (server/motis).

ARG ALPINE_VERSION=3.22

FROM alpine:${ALPINE_VERSION} AS build
ARG MOTIS_VERSION=v2.11.4
WORKDIR /srv/motis

RUN apk add --no-cache curl \
 && curl -fsSL "https://github.com/motis-project/motis/releases/download/${MOTIS_VERSION}/motis-linux-amd64.tar.bz2" \
    | tar -xj ./motis \
 && ./motis --help > /dev/null

# ADD with a URL re-checks the remote file on every build, so a new feed
# busts the cache and the import below runs again.
ADD https://rrgtfsfeeds.s3.amazonaws.com/gtfs_supplemented.zip input/gtfs_supplemented.zip
ADD https://rrgtfsfeeds.s3.amazonaws.com/gtfs_bx.zip input/gtfs_bx.zip
ADD https://rrgtfsfeeds.s3.amazonaws.com/gtfs_b.zip input/gtfs_b.zip
ADD https://rrgtfsfeeds.s3.amazonaws.com/gtfs_m.zip input/gtfs_m.zip
ADD https://rrgtfsfeeds.s3.amazonaws.com/gtfs_q.zip input/gtfs_q.zip
ADD https://rrgtfsfeeds.s3.amazonaws.com/gtfs_si.zip input/gtfs_si.zip
ADD https://rrgtfsfeeds.s3.amazonaws.com/gtfs_busco.zip input/gtfs_busco.zip
ADD https://download.bbbike.org/osm/bbbike/NewYork/NewYork.osm.pbf input/nyc.osm.pbf

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
