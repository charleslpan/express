#!/bin/sh
# Serve the prepared data on $PORT (Vercel's container runtime defaults to 80).
set -eu
sed "s/^  port: .*/  port: ${PORT:-80}/" /srv/motis/config.server.yml > /tmp/motis-config.yml
exec motis server --data /srv/motis/data "$@"
