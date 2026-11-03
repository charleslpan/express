# Express server

The Express backend, deployed as one Vercel project (`express-server`, under
the developer's personal account "charlespan's projects", Hobby plan).

| Path | Service | What |
| --- | --- | --- |
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

## Data

The image is built with the data already imported (`server/motis/Dockerfile`):

- MTA supplemented subway GTFS (includes SIR and planned work), the six MTA bus
  GTFS feeds (Bronx, Brooklyn, Manhattan, Queens, Staten Island, MTA Bus Co.),
  and Geofabrik's New York State OpenStreetMap extract clipped with `osmium`
  to the five boroughs (bbox -74.28,40.48,-73.68,40.93). New Jersey isn't in
  that extract, so walking legs stop at the Hudson.
- 14 days of timetable from the build day (`num_days: 14`). The data goes stale
  unless the image is rebuilt; the nightly rebuild is B3.
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
