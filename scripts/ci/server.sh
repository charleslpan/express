#!/usr/bin/env bash
# CI for apps/api/: typecheck and test the cron function, then build the MOTIS
# image (downloads feeds, runs the import and the build-time smoke test), start
# it, and run the smoke test against it. Needs node, docker, curl, and jq.
set -euo pipefail

cd "$(dirname "$0")/../.."
IMAGE="${IMAGE:-express-motis}"
PORT="${PORT:-8080}"
NAME="express-motis-ci"

echo "::group::apps/api/cron: npm ci, typecheck, test"
(cd apps/api/cron && npm ci --no-audit --no-fund && npm run typecheck && npm test)
echo "::endgroup::"

docker build -t "$IMAGE" apps/api/motis
docker image ls "$IMAGE"

docker rm -f "$NAME" > /dev/null 2>&1 || true
docker run -d --name "$NAME" -e PORT="$PORT" -p "$PORT:$PORT" "$IMAGE" > /dev/null
trap 'status=$?; [ $status -eq 0 ] || docker logs "$NAME"; docker rm -f "$NAME" > /dev/null; exit $status' EXIT

for _ in $(seq 1 60); do
  curl -fsS -o /dev/null "http://localhost:$PORT/api/v6/stoptimes?stopId=us-ny-MTA-NYCSubway_L03&n=1" && break
  sleep 1
done

apps/api/motis/smoke.sh "http://localhost:$PORT"
