# apps/api/

The Express backend: one Vercel project (`express-server`) whose services are
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
  `/api/(.*)` catch-all, which sends everything else to MOTIS.
- `motis/Dockerfile`: downloads MOTIS v2.11.4, the GTFS feeds, and the OSM
  extract, runs `motis import` at build time, and ships only the binary and
  `data/`.
- `motis/config.yml`: MOTIS config. Dataset names must match Transitous's
  (`us-ny-` + the name in Transitous's `feeds/us-ny.json`).
- `motis/entrypoint.sh`: writes the config to `/tmp` with the port from
  `PORT` and starts `motis server`.
- `motis/smoke.sh`: smoke test against any base URL (`SMOKE_TIME` pins the
  query time).
- `motis/smoke-build.sh`: runs `smoke.sh` inside the Docker build (`smoke`
  stage) against the freshly imported data; a failure fails the deployment.
- `cron/api/cron/rebuild.js`: the daily Vercel Cron target. Checks
  `CRON_SECRET`, POSTs `DEPLOY_HOOK_URL?buildCache=false`. The `cron` service
  is a plain Node function with no dependencies; its route sits before the
  `/api/(.*)` catch-all.

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

Needs `curl` and `jq`. CI runs `scripts/ci/server.sh`, which builds the image,
starts it, and runs the smoke test; run it locally the same way with Docker.

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
- `MTA_BUS_TIME_KEY`: set in the project for B2 (bus realtime); not used yet.
- `CRON_SECRET` (sensitive): bearer token Vercel Cron sends to
  `/api/cron/rebuild`.
- `DEPLOY_HOOK_URL` (sensitive): the project's Deploy Hook for `main`.

Never print their values.
