# Express server

The Express backend, deployed as one Vercel project (`express-server`, under
the developer's personal account "charlespan's projects", Hobby plan).

| Path | Service | What |
| --- | --- | --- |
| `/api/vehicles/bus` | `bus` (Node.js Function) | Live bus GPS from MTA Bus Time, filtered to a bounding box. See [Bus positions](#bus-positions). |
| `/api/(.*)` | `motis` (container) | [MOTIS 2](https://github.com/motis-project/motis) v2.11.4 routing for NYC: subway with SIR, and MTA buses. Timetables only for now. |

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
