# server/

The Express backend: one Vercel project (`express-server`) whose services are
declared in `vercel.json`. Today that is MOTIS in `motis/`. See `README.md`
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

## Build and run locally

```sh
docker build -t express-motis server/motis
docker run --rm -e PORT=8080 -p 8080:8080 express-motis
```

Without Docker, download the release tarball, put the feeds under `input/`
next to `config.yml`, and run `motis import` then `motis server` from that
directory (see the Dockerfile for the URLs).

## Test

```sh
server/motis/smoke.sh http://localhost:8080
server/motis/smoke.sh https://express-server-cyan-zeta.vercel.app
```

Needs `curl` and `jq`. CI runs the same script against a freshly built image
(`.github/workflows/ci.yml`, job `motis`, gated by `ci-ok`).

## Deploy

Pushes to `main` deploy production once the project is linked to GitHub with
Root Directory `server`. Until then, deploy the files under `server/` through
the Vercel API or `vercel deploy --prod --scope charlespan-projects` from
`server/`.

## Environment variables

- `PORT`: port MOTIS listens on (container default `80`, Vercel's default).
- `MTA_BUS_TIME_KEY`: set in the project for B2 (bus realtime); not used yet.
