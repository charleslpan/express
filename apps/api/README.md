# Express server

The Express backend, deployed as one Vercel project (`express-server`, under
the developer's personal account "charlespan's projects", Hobby plan).

| Path | Service | What |
| --- | --- | --- |
| `/api/cron/(.*)` | `cron` (Node function) | Daily rebuild trigger, called by Vercel Cron only. |
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

## Data

The image is built with the data already imported (`server/motis/Dockerfile`):

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

## Nightly rebuild

The MTA's supplemented subway feed changes hourly and covers planned work only
7 days ahead, so production is rebuilt from scratch once a day.

1. **Vercel Cron** calls `GET /api/cron/rebuild` on the production deployment
   at `0 9 * * *` (09:00 UTC: 4 am EST, 5 am EDT). Hobby runs it once a day
   somewhere inside that hour (±59 min). Configured in [`vercel.json`](vercel.json).
2. The function ([`cron/api/cron/rebuild.js`](cron/api/cron/rebuild.js)) checks
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
  `vercel crons run /api/cron/rebuild --scope charlespan-projects` from `server/`.

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

Vercel's docs do not say whether deleting a deployment deletes the image it
pushed to the project's container registry (project → **Images**). Check once
the first deployments have aged out: if the image count keeps growing past the
deployment count, delete old untagged images with
`vercel vcr image ls <repo> --untagged` and `vercel vcr image rm <repo> <id>`.

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
