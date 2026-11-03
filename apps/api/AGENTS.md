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
- `motis/smoke.sh`: smoke test against any base URL.
- `bus/`: the bus GPS Function (`api/vehicles/bus.ts`, Node.js, TypeScript),
  the pnpm workspace `@express/bus` (listed in `pnpm-workspace.yaml` by its own
  path, since it sits one level below `apps/*`). Logic lives in `lib/`, tests
  in `test/` (Vitest). It is routed by the
  `/api/vehicles/bus` rewrite ahead of the catch-all. The service needs
  `"framework": "node"` and its `entrypoint` in `vercel.json`: with `root`
  alone Vercel builds nothing. Keep TypeScript below 7: Vercel's Node builder
  type-checks with the local `typescript` package, and TypeScript 7 lacks the
  JavaScript API it calls.

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

Bus Function: `pnpm turbo run lint typecheck test --filter=@express/bus` from the
repository root. CI runs the same through `scripts/ci/node.sh` (`make ci-server`).

## Deploy

The project is linked to GitHub with Root Directory `apps/api`: pushes to a
branch build a preview, and merges to `main` deploy production. To deploy by
hand, run `vercel deploy --prod --scope charlespan-projects` from `apps/api/`.

## Environment variables

- `PORT`: port MOTIS listens on (container default `80`, Vercel's default).
- `MTA_BUS_TIME_KEY`: MTA Bus Time API key, read by the `bus` Function
  (`/api/vehicles/bus`), which answers 503 without it. Never send it to the
  app or log it.
