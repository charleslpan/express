#!/usr/bin/env bash
# Smoke test for the MOTIS server.
# Usage: apps/api/motis/smoke.sh [BASE_URL]   (default http://localhost:8080)
# Needs curl and jq. Exits non-zero on the first failed check.
# Realtime checks need the MTA's live feeds; SMOKE_SKIP_REALTIME=1 skips them.
# SMOKE_TIME (ISO 8601, e.g. 2026-11-04T15:00:00Z) queries at that time instead
# of now; the Docker build sets it so the check does not depend on the hour.
set -euo pipefail

BASE_URL="${1:-${MOTIS_BASE_URL:-http://localhost:8080}}"
BASE_URL="${BASE_URL%/}"
AT="${SMOKE_TIME:+&time=$SMOKE_TIME}"

# Union Square and Bedford Av.
FROM="40.7359,-73.9906"
TO="40.7171,-73.9566"
# 14 St-Union Sq (L), a busy station.
STOP="us-ny-MTA-NYCSubway_L03"
# The only agencies loaded: MTA subway, Staten Island Railway, and buses.
# Anything else (LIRR, Metro-North, PATH, NJ Transit, ferries) is a failure.
ALLOWED_AGENCIES='^(MTA New York City Transit|MTA Bus Company)$'

fail() { echo "FAIL: $*" >&2; exit 1; }

# Retries cover the 503 MOTIS answers after a cold start until its first
# realtime update is in (about 1-2 s).
get() {
  curl -fsS --retry 5 --retry-delay 1 --retry-all-errors --max-time 60 "$1"
}

echo "plan Union Sq -> Bedford Av"
plan="$(get "$BASE_URL/api/v6/plan?fromPlace=$FROM&toPlace=$TO$AT")"
n_it="$(jq '.itineraries | length' <<<"$plan")"
[ "$n_it" -gt 0 ] || fail "no itineraries"
l_legs="$(jq '[.itineraries[].legs[] | select(.mode == "SUBWAY" and .routeShortName == "L")] | length' <<<"$plan")"
[ "$l_legs" -gt 0 ] || fail "no L train legs in $n_it itineraries"
echo "  ok: $n_it itineraries, $l_legs L legs"

echo "stoptimes at $STOP"
st="$(get "$BASE_URL/api/v6/stoptimes?stopId=$STOP&n=10$AT")"
n_st="$(jq '.stopTimes | length' <<<"$st")"
[ "$n_st" -gt 0 ] || fail "no departures at $STOP"
echo "  ok: $n_st departures"

echo "no out-of-scope agencies or modes"
for q in "$FROM&toPlace=40.7527,-73.9772" "$FROM&toPlace=40.7347,-74.0306" "40.7033,-74.0170&toPlace=40.6437,-74.0736"; do
  # Grand Central, Hoboken, and Whitehall -> St. George: places where LIRR,
  # Metro-North, PATH, NJ Transit, or ferries would show up if loaded.
  p="$(get "$BASE_URL/api/v6/plan?fromPlace=$q$AT")"
  bad="$(jq -r --arg ok "$ALLOWED_AGENCIES" '.itineraries[].legs[]
    | select(.mode != "WALK")
    | select(.mode == "FERRY" or ((.agencyName // "") | test($ok) | not))
    | "\(.mode) \(.agencyName // "-") \(.routeShortName // "")"' <<<"$p")"
  [ -z "$bad" ] || fail "out-of-scope legs: $bad"
done
echo "  ok"

if [ "${SMOKE_SKIP_REALTIME:-}" != 1 ]; then
  # The subway runs all night, so live departures are expected at any hour.
  echo "live subway departures at busy stations"
  for stop in L03 127 R16 A27; do
    st="$(get "$BASE_URL/api/v6/stoptimes?stopId=us-ny-MTA-NYCSubway_$stop&n=10")"
    n="$(jq '.stopTimes | length' <<<"$st")"
    rt="$(jq '[.stopTimes[] | select(.realTime)] | length' <<<"$st")"
    echo "  $stop: $rt of $n realTime"
    [ "$rt" -ge $(( (n + 1) / 2 )) ] || fail "under half of departures at $stop are realTime"
  done

  # Alerts reach MOTIS through the adapter, which fills the effect from the
  # MTA's alert type (adapter/alert_types.json) and writes the type itself into
  # effect_detail, which MOTIS passes on as effectDetail (it drops
  # severity_level; the app maps the type to its severity). Take alerts from the
  # MTA's own feed that name a line at a stop, and look for one on a departure
  # of that line (and direction) at that stop, with the mapped effect and the
  # type. Several are tried: a skipped stop has no departures of its line to
  # carry the alert.
  echo "MTA subway alert on a matching departure, with its mapped effect and type"
  types="$(dirname "$0")/adapter/alert_types.json"
  alerts="$(get "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/camsys%2Fsubway-alerts.json")"
  candidates="$(jq -c --slurpfile t "$types" '
    $t[0] as $t
    | [.entity[] | .alert as $a
       | ($a["transit_realtime.mercury_alert"].alert_type // "") as $type
       | ($type | ltrimstr($t.plannedPrefix)) as $base
       | {header: ([$a.header_text.translation[] | select(.language == "en") | .text][0]),
          effect: (($t.types[$type] // $t.types[$base] // $t.fallback).effect),
          type: $type}
         + ([$a.informed_entity[] | select(.stop_id and .route_id)][0]
            | {route: .route_id, stop: .stop_id, dir: (.direction_id // null)})
       | select(.stop)]
    | .[:25][]' <<<"$alerts")"
  found=""
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    stop="$(jq -r .stop <<<"$c")"
    st="$(get "$BASE_URL/api/v6/stoptimes?stopId=us-ny-MTA-NYCSubway_$stop&n=30")"
    hit="$(jq -r --argjson c "$c" '
      [.stopTimes[]
       | select(.routeId == "us-ny-MTA-NYCSubway_\($c.route)")
       | select($c.dir == null or .directionId == ($c.dir | tostring))
       | .place.alerts[]? | select(.headerText == $c.header)] as $hits
      | if ($hits | length) == 0 then "none"
        elif any($hits[]; .effect == $c.effect and .effectDetail == ($c.type | if . == "" then null else . end))
          then "ok"
        else "effect \($hits[0].effect // "missing") and effectDetail \($hits[0].effectDetail // "missing")" end' <<<"$st")"
    case "$hit" in
      ok) found="$c"; break ;;
      none) ;;
      *) fail "alert $(jq -r '"\(.type) on \(.route) at \(.stop)"' <<<"$c") has $hit, expected $(jq -r '"\(.effect) and \(.type)"' <<<"$c")" ;;
    esac
  done <<<"$candidates"
  [ -n "$candidates" ] || fail "the MTA's subway alerts name no line at a stop"
  [ -n "$found" ] || fail "none of $(wc -l <<<"$candidates") MTA alerts appears on a matching departure"
  echo "  ok: $(jq -r '"\(.type) on the \(.route) at \(.stop): \(.effect), effectDetail \(.type)"' <<<"$found")"

  echo "realtime age and match rate in /metrics"
  m="$(get "$BASE_URL/metrics")"
  ts="$(awk '/^nigiri_gtfsrt_feed_timestamp_seconds\{tag="us-ny-MTA-NYCSubway"\}/ {print int($2)}' <<<"$m")"
  age=$(( $(date +%s) - ${ts:-0} ))
  echo "  subway feed age ${age}s"
  [ "$age" -lt 300 ] || fail "subway realtime is ${age}s old"
  awk '/^current_trips_running_scheduled(_with_realtime)?_count\{.*NYCSubway/ {
         if ($1 ~ /with_realtime/) live = $NF; else all = $NF }
       END { printf "  %d of %d running subway trips have realtime\n", live, all }' <<<"$m"
fi

echo "smoke passed against $BASE_URL"
