# apps/api/

The Express backend: one Vercel project (`express`) whose services are
declared in `vercel.json`, and the pnpm workspace `@express/api` (see the root
[`AGENTS.md`](../../AGENTS.md)). Today that is MOTIS in `motis/`. See `README.md`
for what is deployed and the measured numbers.

## Vercel account

Everything goes under the personal account **charlespan's projects**
(team id `team_DQArotHEGEevMkHtaaehgB2F`, slug `charlespan-projects`), never
the Stage team. Pass `--scope charlespan-projects` (CLI) or the team id (API)
on every call.

## Layout

- `vercel.json`: services and rewrites. Add new routes **before** the
  `/api/(.*)` catch-all, which sends everything else to MOTIS. `/metrics` also
  goes to MOTIS (realtime age and match rate). It also pins the region
  (`iad1`; Hobby allows one), caps each service's `maxDuration` through its
  own `functions` glob (top-level `functions` is invalid with `services`), and
  sets `Vercel-CDN-Cache-Control` on MOTIS's cacheable routes (stoptimes, trip,
  map), since MOTIS sends no `Cache-Control` itself. Keep `plan` uncached.
- `motis/Dockerfile`: downloads MOTIS v2.11.4, the GTFS feeds, and the OSM
  extract, runs `motis import` at build time, builds the adapter's index from
  the same files, and ships the binary, `data/`, and the adapter.
- `motis/config.yml`: MOTIS config. Dataset names must match Transitous's
  (`us-ny-` + the name in Transitous's `feeds/us-ny.json`).
- `motis/entrypoint.sh`: writes the config to `/tmp` with the port from
  `PORT`, starts the adapter, then `motis server`, and exits when either
  exits (under `tini`), so Vercel replaces the instance.
- `motis/adapter/`: the realtime adapter MOTIS polls on `127.0.0.1:8081`.
  `matcher.py` matches MTA subway realtime trips to static trips (delete it
  if MOTIS ever does this itself); `adapter.py` serves `/subway/<feed>` and
  `/bus/<dataset>`; `upstream.py` fetches every feed in parallel at start for
  MOTIS's first cycle (shortening the cold start's 503s), and the adapter's
  server keeps a listen backlog of 64, since MOTIS opens all its polls at
  once; `build_index.py` runs at image build; `record.py` records live feeds as test fixtures and prints match rates. `alerts.py` fills the
  MTA alerts' standard effect, cause, and severity from `alert_types.json`,
  and `effect_detail` with the MTA's type (MOTIS drops `severity_level` but
  passes `effectDetail` on, which the app maps to a severity), for
  `/alerts/subway` and `/alerts/bus/<dataset>`. To add a feed, add it to
  `adapter.py` and a `rt` entry to `config.yml` (alert feeds first in a
  dataset's list: the last feed listed sets its feed-timestamp metric).
- `motis/smoke.sh`: smoke test against any base URL (`SMOKE_TIME` pins the
  query time).
- `motis/smoke-build.sh`: runs `smoke.sh` inside the Docker build (`smoke`
  stage) against the freshly imported data; a failure fails the deployment.
- `ignore-build.sh`: Vercel's Ignored Build Step, set in the project's
  settings (`bash ignore-build.sh`; Vercel ignores the `motis` service's
  `ignoreCommand`). Previews build only when the API's paths (the same as CI's
  `server` filter) changed since the branch left `main`; production always
  builds. Add a path there if the API starts depending on one outside them.
- `cron/`: the daily Vercel Cron target, the pnpm workspace `@express/cron`
  (listed in `pnpm-workspace.yaml`, shared tsconfig and ESLint config).
  `api/cron/rebuild.ts` is the entrypoint; `lib/rebuild.ts` checks
  `CRON_SECRET`, runs `lib/prune.ts` (deletes old `motis` registry images,
  never production's), and POSTs `DEPLOY_HOOK_URL?buildCache=false`. Its route sits
  before the `/api/(.*)` catch-all. Keep `typescript` below 7 (Vercel's
  builder crashes on TS 7).
- `bus/`: the bus GPS Function (`api/vehicles/bus.ts`, Node.js, TypeScript),
  the pnpm workspace `@express/bus` (listed in `pnpm-workspace.yaml` by its own
  path, since it sits one level below `apps/*`). Logic lives in `lib/`, tests
  in `test/` (Vitest). It is routed by the
  `/api/vehicles/bus` rewrite ahead of the catch-all. The service needs
  `"framework": "node"` and its `entrypoint` in `vercel.json`: with `root`
  alone Vercel builds nothing. Keep TypeScript below 7: Vercel's Node builder
  type-checks with the local `typescript` package, and TypeScript 7 lacks the
  JavaScript API it calls.
- `alerts/`: the line status Function (`api/alerts.ts`, `GET /api/alerts`),
  the pnpm workspace `@express/alerts`, set up like `bus/`. Its
  `lib/alert-types.ts` is a checked copy of `motis/adapter/alert_types.json`
  (a test fails when they differ): edit the JSON, then mirror it there and in
  TransitKit's `MTAAlertType.swift` (its severities, also checked).

## Build and run locally

```sh
docker build -t express-motis apps/api/motis
docker run --rm -e PORT=8080 -p 8080:8080 express-motis
```

Without Docker, download the release tarball, put the feeds under `input/`
next to `config.yml`, and run `motis import` then `motis server` from that
directory (see the Dockerfile for the URLs).

## Test

```sh
apps/api/motis/smoke.sh http://localhost:8080
apps/api/motis/smoke.sh https://express-server-cyan-zeta.vercel.app
```

Needs `curl` and `jq`. The realtime checks need the MTA feeds
(`SMOKE_SKIP_REALTIME=1` skips them). CI runs `scripts/ci/server.sh`, which builds the image,
starts it, and runs the smoke test; run it locally the same way with Docker.

Adapter unit tests (need `protobuf` and `gtfs-realtime-bindings`):

```sh
cd apps/api/motis/adapter && python3 -m unittest discover -s tests
```

Match rates against the live feeds, and new fixtures (needs an index built
with `build_index.py` from the same GTFS zips):

```sh
python3 record.py subway_index.json [tests/fixtures/<name>]
```

Cron function checks (CI runs them through `scripts/ci/node.sh`):

```sh
pnpm turbo run lint typecheck test --filter=@express/cron
```

Bus and alerts Functions: `pnpm turbo run lint typecheck test --filter=@express/bus`
(or `@express/alerts`) from the repository root. CI runs the same through `scripts/ci/node.sh` (`make ci-server`).

## Deploy

The project is linked to GitHub with Root Directory `apps/api`: pushes to a
branch build a preview, and merges to `main` deploy production. To deploy by
hand, run `vercel deploy --prod --scope charlespan-projects` from `apps/api/`.

## Nightly rebuild

Vercel Cron (`crons` in `vercel.json`, `0 9 * * *` UTC, ±59 min on Hobby)
calls `/api/cron/rebuild`, which triggers a production build with no build
cache. The build's smoke stage is the health check; a failing build leaves the
previous production deployment serving and Vercel emails the developer. Do not
add a GitHub Actions cron or an issue bot for this. Rebuild by hand, roll back,
and retention: see `README.md`, "Nightly rebuild". After an Instant Rollback,
new builds are not promoted until someone runs `vercel promote`.

## Environment variables

- `PORT`: port MOTIS listens on (container default `80`, Vercel's default).
- `MTA_BUS_TIME_KEY`: MTA Bus Time key, read by the motis adapter (MOTIS never
  sees it; without it, bus realtime is off and the bus feeds answer 404) and by
  the `bus` Function (`/api/vehicles/bus`), which answers 503 without it.
  Never send it to the app or log it.
- `CRON_SECRET` (sensitive): bearer token Vercel Cron sends to
  `/api/cron/rebuild`.
- `DEPLOY_HOOK_URL` (sensitive): the project's Deploy Hook for `main`.
- `VERCEL_API_TOKEN` (sensitive, Production, optional): Vercel token the cron
  uses to prune `motis` images. Without it the cron warns and still rebuilds.

Never print their values.
