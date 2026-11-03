#!/usr/bin/env bash
# Build-time health check: serve the freshly imported data and run smoke.sh
# against it, so a bad feed fails the image build and never reaches
# production. Runs from /srv/motis in the Dockerfile's smoke stage.
set -euo pipefail

PORT=8080

# Query tomorrow (or the next weekday) at 15:00 UTC, 10 or 11 am in New York,
# so the check tests the data rather than whatever runs at build hour.
now="$(date -u +%s)"
day=$(( now / 86400 + 1 ))
while [ "$(date -u -d "@$(( day * 86400 ))" +%u)" -gt 5 ]; do day=$(( day + 1 )); done
SMOKE_TIME="$(date -u -d "@$(( day * 86400 + 15 * 3600 ))" +%Y-%m-%dT%H:%M:%SZ)"
export SMOKE_TIME
echo "smoke time $SMOKE_TIME"

sed "s/^  port: .*/  port: $PORT/" config.server.yml > data/config.yml
./motis server --data data > motis-server.log 2>&1 &
pid=$!
trap 'kill "$pid" 2>/dev/null || true' EXIT

for _ in $(seq 120); do
  curl -fsS -o /dev/null "http://localhost:$PORT/api/v6/stoptimes?stopId=us-ny-MTA-NYCSubway_L03&n=1" 2>/dev/null && break
  kill -0 "$pid" 2>/dev/null || { cat motis-server.log >&2; echo "FAIL: server exited" >&2; exit 1; }
  sleep 0.5
done

bash smoke.sh "http://localhost:$PORT"
