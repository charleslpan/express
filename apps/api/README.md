# Express server

The Express backend, deployed as one Vercel project (`express-server`, under
the developer's personal account "charlespan's projects", Hobby plan).

| Path | Service | What |
| --- | --- | --- |
| `/api/vehicles/bus` | `bus` (Node.js Function) | Live bus GPS from MTA Bus Time, filtered to a bounding box. See [Bus positions](#bus-positions). |
| `/api/alerts` | `alerts` (Node.js Function) | MTA subway and bus service alerts per line. See [Line status](#line-status). |
| `/api/cron/(.*)` | `cron` (Node function, TypeScript) | Daily rebuild trigger, called by Vercel Cron only. |
| `/api/(.*)` | `motis` (container) | [MOTIS 2](https://github.com/motis-project/motis) v2.11.4 routing for NYC: subway with SIR, and MTA buses, with live subway (and bus, once `MTA_BUS_TIME_KEY` is set) data. |
| `/metrics` | `motis` (container) | MOTIS's Prometheus metrics: realtime data age and match rate. |

Production: <https://express-server-cyan-zeta.vercel.app> (also
`express-server-charlespan-projects.vercel.app`). Example:

```sh
curl 'https://express-server-cyan-zeta.vercel.app/api/v6/plan?fromPlace=40.7359,-73.9906&toPlace=40.7171,-73.9566'
curl 'https://express-server-cyan-zeta.vercel.app/api/v6/stoptimes?stopId=us-ny-MTA-NYCSubway_L03&n=10'
```

Vercel passes the original path to the service, so `/api/v6/plan` reaches
MOTIS as `/api/v6/plan`. New routes go **before** the `/api/(.*)` catch-all in
[`vercel.json`](vercel.json).

## Bus positions

`GET /api/vehicles/bus?bbox=minLat,minLon,maxLat,maxLon[&routes=M15,B44%2B]`

Live bus positions from MTA Bus Time's GTFS-RT vehicle positions feed, decoded
with Google's `gtfs-realtime-bindings`. The Bus Time key stays on the server
(`MTA_BUS_TIME_KEY`), and the app never calls MTA servers itself, as MTA's
terms require. Code in [`bus/`](bus/).

```sh
curl 'https://express-server-cyan-zeta.vercel.app/api/vehicles/bus?bbox=40.70,-74.02,40.72,-73.98&routes=M15,M15%2B'
```

Query:

- `bbox` (required): `minLat,minLon,maxLat,maxLon` in degrees, each side at
  most 1°, which covers all five boroughs.
- `routes` (optional): up to 50 comma-separated GTFS `route_id`s, matched
  exactly. Select Bus Service routes end in `+` (`M15+`), which must be sent as
  `%2B`.

Response (`200`, `application/json`):

```json
{
  "updatedAt": 1793731200,
  "vehicles": [
    {
      "id": "MTA NYCT_7582",
      "route": "M15",
      "directionId": 0,
      "tripId": "OH_D6-Weekday-SDon-108500_M15_402",
      "headsign": null,
      "lat": 40.7075,
      "lon": -74.0021,
      "bearing": 212.4,
      "timestamp": 1793731188
    }
  ]
}
```

| Field | Type | Meaning |
| --- | --- | --- |
| `updatedAt` | number or null | Feed header time, Unix seconds. |
| `id` | string | Bus Time vehicle id (`MTA NYCT_…` or `MTABC_…`). |
| `route` | string or null | GTFS `route_id`, the same as in the bus timetables MOTIS loads. |
| `directionId` | 0, 1, or null | GTFS `direction_id`. |
| `tripId` | string or null | GTFS `trip_id` from the bus timetables MOTIS loads (`MQ_D6-Weekday-081500_M9_67` for NYCT, `47352355-CPPD6-CP_D6-Weekday-04` for MTA Bus Company). Buses are often interlined, so the trip can belong to another route than `route` (an M9 bus running an M21 trip). |
| `headsign` | null | Always null: GTFS-RT vehicle positions carry no headsign. Look it up from MOTIS (`/api/v6/trip`) by `tripId` when a bus is tapped. |
| `lat`, `lon` | number | GPS position, 5 decimals (about 1 m). |
| `bearing` | number or null | Degrees clockwise from true north. |
| `timestamp` | number or null | Time of the GPS fix, Unix seconds. |

Errors answer `{ "error": "…" }` with `Cache-Control: no-store`: `400` for a
bad query, `405` for methods other than GET and HEAD, `502` when Bus Time fails,
`503` when `MTA_BUS_TIME_KEY` is not set.

Caching: the decoded fleet (every bus, about 500 KB of JSON) is kept in Vercel's
Runtime Cache for 30 s, shared by every instance and every bbox, so Bus Time is
fetched at most about once per 30 s; misses on one instance share one fetch.
Responses carry `Cache-Control: public, max-age=0, s-maxage=30`, so the CDN
also answers repeats of the same URL. The CDN strips `s-maxage` from what
the client sees (`public, max-age=0`).

Measured on Nov 3, 2026 at 19:20 UTC: Bus Time answered in 69 ms with 350 KB of
protobuf for 2,639 buses on 288 routes; every bus had a position, route, trip,
direction, bearing, and fix time, the oldest fix 127 s old. A whole-city
response is about 540 KB, well under Vercel's 4.5 MB limit; a peak-hour fleet
of about 5,000 buses would be about 1 MB.

Tests run on twelve buses recorded from the real Bus Time feed on Nov 3, 2026
(`bus/test/fixtures/bus-time-2026-11-03.pb`, header included):

```sh
pnpm turbo run lint typecheck test --filter=@express/bus
```

## Line status

`GET /api/alerts?lines=A,C,M15+`

The MTA's subway and bus service alerts (`camsys%2Fsubway-alerts.json` and
`camsys%2Fbus-alerts.json`, no key), per line, with the standard GTFS-RT
effect, cause, and severity filled from the MTA's alert type by the same table
the MOTIS adapter uses (see [Alerts](#alerts)). Every alert in the feeds is
returned, future ones included (the line page shows upcoming work); filtering
by time is the app's. Code in [`alerts/`](alerts/).

```sh
curl 'https://express-server-cyan-zeta.vercel.app/api/alerts?lines=A,L,M15+'
```

Query: `lines` (required), up to 50 comma-separated GTFS `route_id`s, matched
exactly (`A`, `6X`, `SI`, `GS`, `M15+`, `BM1`). `+` is read literally, so
`M15+` works as typed; `%2B` works too.

Response (`200`, `application/json`): every requested line, with `[]` where it
has no alerts.

```json
{
  "updatedAt": { "subway": 1793741003, "bus": 1793741361 },
  "lines": {
    "2": [
      {
        "id": "lmm:alert:274734:26",
        "type": "Delays",
        "effect": "SIGNIFICANT_DELAYS",
        "cause": "UNKNOWN_CAUSE",
        "severity": "WARNING",
        "activePeriods": [{ "start": 1793740456, "end": 1793742540 }],
        "header": "Wakefield-241 St-bound [2] and Eastchester-Dyre Av-bound [5] trains are running with delays …",
        "description": null,
        "affected": [{ "stopId": null, "directionId": null }]
      }
    ]
  }
}
```

| Field | Type | Meaning |
| --- | --- | --- |
| `updatedAt` | object | Each feed's header time, Unix seconds (or null). |
| `id` | string | The MTA's alert id, also the GTFS-RT entity id MOTIS reads. An alert on several lines appears under each. |
| `type` | string or null | The MTA's own alert type (`Planned - Part Suspended`, `Boarding Change`). |
| `effect` | string | GTFS-RT effect (`NO_SERVICE`, `REDUCED_SERVICE`, `SIGNIFICANT_DELAYS`, `DETOUR`, `ADDITIONAL_SERVICE`, `MODIFIED_SERVICE`, `STOP_MOVED`, `OTHER_EFFECT`), the same MOTIS puts on departures and legs. |
| `cause` | string | `MAINTENANCE` for planned work, else `UNKNOWN_CAUSE`. |
| `severity` | string | `INFO`, `WARNING`, or `SEVERE`. |
| `activePeriods` | array | `{ start, end }` in Unix seconds; either may be null (open-ended). MOTIS returns these as `communicationPeriod`. |
| `header`, `description` | string, string or null | English plain text (the feeds also carry HTML, not returned). The MTA writes lines as `[A]`. |
| `affected` | array | This line's informed entities: `stopId` is a GTFS parent stop (`A24`, without the MOTIS dataset prefix) or null for the whole line; `directionId` is 0, 1, or null for both. Bus alerts name lines only. |

Errors answer `{ "error": "…" }` with `Cache-Control: no-store`: `400` for a
bad query, `405` for methods other than GET and HEAD, `502` when either MTA
feed fails.

Caching: both feeds are decoded into one per-line index kept in Vercel's
Runtime Cache for 60 s (`getCache()`, `ttl: 60`), shared by every instance, so
the MTA is asked at most about once a minute; misses on one instance share one
fetch. Responses carry `Cache-Control: public, max-age=0, s-maxage=60`.

Tests run on both feeds as recorded on Nov 3, 2026 at about 21:30 UTC
(`alerts/test/fixtures/`):

```sh
pnpm turbo run lint typecheck test --filter=@express/alerts
```

## Data

The image is built with the data already imported (`apps/api/motis/Dockerfile`):

- MTA supplemented subway GTFS (includes SIR and planned work), the six MTA bus
  GTFS feeds (Bronx, Brooklyn, Manhattan, Queens, Staten Island, MTA Bus Co.),
  and Geofabrik's New York State OpenStreetMap extract clipped with `osmium`
  to the five boroughs (bbox -74.28,40.48,-73.68,40.93). New Jersey isn't in
  that extract, so walking legs stop at the Hudson.
- 14 days of timetable from the build day (`num_days: 14`). The image is
  rebuilt every night (see [Nightly rebuild](#nightly-rebuild)).
- Dataset names match Transitous (`us-ny-MTA-NYCSubway`,
  `us-ny-MTA-BusBronx`, …), so stop and trip ids such as
  `us-ny-MTA-NYCSubway_L03` are the same on both servers and the app can switch
  by base URL alone.
- No tiles, geocoding, or reverse geocoding.

## Realtime

A small adapter (`motis/adapter/`) runs in the same container and serves
corrected feeds to MOTIS on `127.0.0.1:8081`; MOTIS polls it every 30 s and
each poll makes one upstream fetch.

- **Subway**: the 8 MTA subway GTFS-RT feeds. MOTIS resolves realtime trips by
  trip id, and the MTA's realtime ids (`071900_A..S58R`) are not the static ids
  (`BFA26GEN-A047-Weekday-00_071900_A..S58R`); MOTIS has no NYC matching of its
  own. The adapter matches each live train to the one static trip with the same
  route token, direction, origin time, and service date (path as tie-breaker,
  `6X`/`7X`/`FX`/`SS` read as `6`/`7`/`F`/`SI`), then sets the static
  `start_time`, because MOTIS skips a trip whose `start_time` differs from its
  scheduled first departure. Live trains no scheduled trip matches go to MOTIS
  as ADDED trips with their own times, never onto the nearest scheduled trip.
  The NYCT extension fields pass through unchanged.
- **Bus**: MTA Bus Time trip updates (`MTA_BUS_TIME_KEY`). It is one
  fleet-wide feed but MOTIS attaches realtime per dataset, so the adapter
  fetches it once per cycle (the MTA allows one fleet-wide call per 30 s) and
  hands each bus dataset its own routes.
- **Alerts**: the MTA's subway and bus service alerts (no key). The MTA leaves
  the standard `effect`, `cause`, and `severity_level` empty and says what an
  alert is only in its `mercury_alert` extension's `alert_type`, so MOTIS would
  answer `UNKNOWN_EFFECT` for all of them. The adapter fills the three fields
  from [`motis/adapter/alert_types.json`](motis/adapter/alert_types.json)
  (fields the feed sets are kept; `Planned - …` types get `cause:
  MAINTENANCE`; an unknown type gets `OTHER_EFFECT` and is logged once) and
  changes nothing else. The bus alerts feed is fetched once per cycle and each
  bus dataset gets the alerts naming its routes. MOTIS attaches them to
  departures (`place.alerts`) and legs, with the MTA's `active_period` as
  `communicationPeriod`, whatever its time. Alert feeds are listed first per
  dataset in `config.yml`: the feed-timestamp metric is per dataset and the
  last feed listed sets it.
- **Cold start**: MOTIS answers 503 (`motis is starting up`) until its first
  realtime update is in, about 1.5 s after start; retry after a second.
  `/metrics` and `/api/v1/health` answer meanwhile.
- **Data age**: `nigiri_gtfsrt_feed_timestamp_seconds{tag="us-ny-MTA-NYCSubway"}`
  in `/metrics` is the MTA's own timestamp of the last subway feed MOTIS read
  (0 if the last fetch failed). Show the "may not be real time" notice when
  `now - timestamp` is over about 90 s or the value is 0. After an idle pause
  the first answer can be as old as the pause; MOTIS's overdue poll runs at
  once, so the next refresh is current.
- **Match rate**: `current_trips_running_scheduled_with_realtime_count` over
  `current_trips_running_scheduled_count` (per tag) in `/metrics` is the share
  of trains running now with live data; it drops if matching breaks.
  `nigiri_gtfsrt_trip_resolve_error_total` should stay 0. The adapter logs
  matched / added / dropped per feed on every poll.

## Nightly rebuild

The MTA's supplemented subway feed changes hourly and covers planned work only
7 days ahead, so production is rebuilt from scratch once a day.

1. **Vercel Cron** calls `GET /api/cron/rebuild` on the production deployment
   at `0 9 * * *` (09:00 UTC: 4 am EST, 5 am EDT). Hobby runs it once a day
   somewhere inside that hour (±59 min). Configured in [`vercel.json`](vercel.json).
2. The function ([`cron/lib/rebuild.ts`](cron/lib/rebuild.ts)) checks
   `Authorization: Bearer $CRON_SECRET` and POSTs the project's Deploy Hook
   with `?buildCache=false`, so the Docker build downloads fresh feeds and
   re-imports them.
3. The Docker build runs the **health check** in its `smoke` stage
   ([`motis/smoke-build.sh`](motis/smoke-build.sh)): it serves the freshly
   imported data inside the build and runs [`motis/smoke.sh`](motis/smoke.sh)
   against it (Union Square → Bedford Av still returns the L, stoptimes at
   14 St–Union Sq return departures, no out-of-scope agencies). It queries the
   next weekday at 15:00 UTC rather than build time, so the check tests the
   data, not the 4 am service pattern. A failure fails the build.
4. A failed build never gets the production domains: Vercel assigns them only
   to a deployment that reaches Ready, so the previous production deployment
   keeps serving. The developer hears of it through Vercel's failed-deployment
   notification (Account Settings → Notifications → Deployment Failures, on by
   default for the deployment's creator; keep it on for this project).

### Secrets and env vars (project `express-server`, Production)

| Name | What | Who sets it |
| --- | --- | --- |
| `CRON_SECRET` | Random string (≥ 16 chars). Vercel Cron sends it as `Authorization: Bearer …`; the function rejects anything else. | Developer, Sensitive |
| `DEPLOY_HOOK_URL` | URL of the project's Deploy Hook for branch `main` (Settings → Git → Deploy Hooks). Anyone with it can trigger a build. | Developer, Sensitive |

Without either, the function answers 401 or 500 and nothing rebuilds.

### Rebuild by hand

- Dashboard: Deployments → latest production → ⋯ → **Redeploy**, untick
  "Use existing Build Cache".
- Or POST the hook: `curl -X POST "$DEPLOY_HOOK_URL?buildCache=false"`.
- Or run the cron now: Settings → Cron Jobs → **Run**, or
  `vercel crons run /api/cron/rebuild --scope charlespan-projects` from `apps/api/`.

### Roll back

A failed nightly build needs no rollback; production stays on the last good
deployment. If a build passed the smoke test but serves bad data:

- Dashboard: Deployments → the previous production deployment → **Instant
  Rollback**, or `vercel rollback --scope charlespan-projects`. Hobby can only
  roll back to the immediately previous production deployment.
- After a rollback Vercel stops assigning production domains to new
  deployments, so the next nightly build will **not** go live until you
  promote one (`vercel promote <deployment-url>` or **Promote** in the
  dashboard). Fix the cause first.

### Old deployments and images

Cleanup is Vercel's own **Deployment Retention Policy** (Settings → Build and
Deployment), not a script. Recommended for this project: Canceled 1 week,
Errored 1 week, Preview 1 week, Production 1 week. Vercel always keeps the
current production deployment and, on Hobby, the last 3 Ready production
deployments, so rollback still works. That keeps roughly 7–10 deployments
(each ≈ 181 MB of image) instead of the 30-day default's ≈ 30+ against Hobby's
10 GB deployment storage and VCR's 50 images per repository.

Each build pushes its image to the project's registry repository `motis`,
tagged with the deployment id (`motis:dpl_…`; project → **Images**). Vercel's
docs do not say whether deleting a deployment deletes that image. Check once
the first deployments have aged out (after Nov 10, 2026 with a 1-week policy):
if `vercel vcr image ls motis` lists tags for deployments that no longer
exist, delete those with `vercel vcr image rm motis <image-id>`.

## Measurements

Measured on Nov 3, 2026 against deployment `dpl_927ee3vvdAR6QWd7ib4Ugqr9PkG1`
(iad1, built from the BBBike extract), and locally with the same release and
data. The clipped Geofabrik extract should be the same size or smaller.

| What | Value | How |
| --- | --- | --- |
| Vercel accepts the image | Yes, no trimming needed | Production deploy READY; the 250 MB Function limit does not apply to container images (VCR limits: 2 GB per compressed layer, 15 GB per image) |
| Image, compressed | ≈ 181 MB (zstd level 3, as Vercel pushes it) | Data 161 MB + binary 16.5 MB + Alpine ≈ 3.5 MB, compressed locally |
| Image, unpacked | ≈ 498 MB | Data 434 MB + binary 56 MB + Alpine 8 MB |
| Vercel build | 81 s total: 63 s image build (downloads ≈ 12 s, `motis import` ≈ 40 s), 9 s push | Build log; 2 vCPU / 8 GB Hobby machine |
| Server ready after start | ≈ 0.2–0.3 s | Local; Vercel logs show `listening` right after start |
| Cold start to first answer | 1.3–1.5 s from the client (3 cold starts); the container starts listening ≈ 1.2 s after the request arrives | `curl` time to first byte from a US-hosted sandbox, plus runtime logs |
| Warm latency (Vercel, client-side) | plan 0.14–0.45 s, stoptimes 0.05–0.10 s | `curl` total time; edge round trip alone ≈ 0.02 s |
| Warm plan compute (local) | 0.05–0.16 s | MOTIS on 2 cores |
| Memory | 246 MB after start, 410–430 MB resident after 25 plans | Local `/proc` VmRSS/VmHWM; mostly memory-mapped data |
| CPU per cold start | ≈ 0.3 CPU-s to start and answer the first request | Local `/proc/<pid>/stat` |
| CPU per plan | ≈ 0.1 CPU-s | Local, 25 varied plans used 2.7 CPU-s |
| Instances | 1 vCPU (`n_threads=1` in Vercel logs) | Runtime logs |

Hobby includes 4 Active CPU-hours a month (14,400 CPU-s): at ≈ 0.1 CPU-s per
plan that is on the order of 140,000 plans a month, and cold starts are cheap
(≈ 0.3 CPU-s each). Vercel's docs say production instances scale down after 5
idle minutes, but the logs showed shutdowns 35–65 s after the last request, so
expect a 1.3–1.5 s cold start on most first requests after a quiet minute.

Vercel's per-function memory and CPU metrics need Observability Plus (Pro), so
on Hobby read them from the project's **Usage** tab instead; the local numbers
above are the same binary and data.

## Findings from the first deploys

- The Docker build has network access, so feeds download during the build.
- Builds run `buildah` with `--layers`, but every build so far started with
  "Buildah store: cold" (no layer cache), as do GitHub runners, so each build
  downloads fresh feeds. If Vercel starts caching layers, the nightly rebuild
  (B3) needs a cache-bust before the download steps.
- Every download (`curl --retry 5 --retry-all-errors`, exponential backoff)
  retries, so one flaky host doesn't fail a build.
- **Why not BBBike:** its NYC extract (the pilot's first choice) timed out from
  both GitHub runners and Vercel builders, mirrors included. We use Geofabrik's
  New York State extract clipped to the five boroughs; v1 is MTA-only, so
  losing New Jersey walking costs nothing.
- The container writes its runtime config to `/tmp`, which works.
- The project is linked to GitHub with Root Directory `server`: pushes build
  previews, and `main` deploys production.
- Vercel Authentication covers previews only, so production is public.
