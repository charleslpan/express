#!/usr/bin/env bash
# Smoke test for the MOTIS server.
# Usage: server/motis/smoke.sh [BASE_URL]   (default http://localhost:8080)
# Needs curl and jq. Exits non-zero on the first failed check.
set -euo pipefail

BASE_URL="${1:-${MOTIS_BASE_URL:-http://localhost:8080}}"
BASE_URL="${BASE_URL%/}"

# Union Square and Bedford Av.
FROM="40.7359,-73.9906"
TO="40.7171,-73.9566"
# 14 St-Union Sq (L), a busy station.
STOP="us-ny-MTA-NYCSubway_L03"
# The only agencies loaded: MTA subway, Staten Island Railway, and buses.
# Anything else (LIRR, Metro-North, PATH, NJ Transit, ferries) is a failure.
ALLOWED_AGENCIES='^(MTA New York City Transit|MTA Bus Company)$'

fail() { echo "FAIL: $*" >&2; exit 1; }

get() {
  curl -fsS --retry 3 --retry-delay 2 --retry-all-errors --max-time 60 "$1"
}

echo "plan Union Sq -> Bedford Av"
plan="$(get "$BASE_URL/api/v6/plan?fromPlace=$FROM&toPlace=$TO")"
n_it="$(jq '.itineraries | length' <<<"$plan")"
[ "$n_it" -gt 0 ] || fail "no itineraries"
l_legs="$(jq '[.itineraries[].legs[] | select(.mode == "SUBWAY" and .routeShortName == "L")] | length' <<<"$plan")"
[ "$l_legs" -gt 0 ] || fail "no L train legs in $n_it itineraries"
echo "  ok: $n_it itineraries, $l_legs L legs"

echo "stoptimes at $STOP"
st="$(get "$BASE_URL/api/v6/stoptimes?stopId=$STOP&n=10")"
n_st="$(jq '.stopTimes | length' <<<"$st")"
[ "$n_st" -gt 0 ] || fail "no departures at $STOP"
echo "  ok: $n_st departures"

echo "no out-of-scope agencies or modes"
for q in "$FROM&toPlace=40.7527,-73.9772" "$FROM&toPlace=40.7347,-74.0306" "40.7033,-74.0170&toPlace=40.6437,-74.0736"; do
  # Grand Central, Hoboken, and Whitehall -> St. George: places where LIRR,
  # Metro-North, PATH, NJ Transit, or ferries would show up if loaded.
  p="$(get "$BASE_URL/api/v6/plan?fromPlace=$q")"
  bad="$(jq -r --arg ok "$ALLOWED_AGENCIES" '.itineraries[].legs[]
    | select(.mode != "WALK")
    | select(.mode == "FERRY" or ((.agencyName // "") | test($ok) | not))
    | "\(.mode) \(.agencyName // "-") \(.routeShortName // "")"' <<<"$p")"
  [ -z "$bad" ] || fail "out-of-scope legs: $bad"
done
echo "  ok"

echo "smoke passed against $BASE_URL"
