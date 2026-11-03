#!/bin/sh
# Start the realtime adapter, then MOTIS, under tini (see the Dockerfile).
# If either exits, so does the container, and Vercel starts a fresh one.
set -eu
sed "s/^  port: .*/  port: ${PORT:-80}/" /srv/motis/config.server.yml > /tmp/motis-config.yml

rm -f /tmp/adapter.ready
python3 /srv/adapter/adapter.py &
# MOTIS polls the adapter as soon as it starts and counts that first cycle as
# its realtime update even when every fetch fails, so wait until the adapter
# listens (it takes well under a second).
i=0
until [ -e /tmp/adapter.ready ]; do
  i=$((i + 1))
  [ "$i" -le 200 ] || { echo "adapter did not start" >&2; exit 1; }
  sleep 0.05
done

motis server --data /srv/motis/data "$@" &
wait -n
