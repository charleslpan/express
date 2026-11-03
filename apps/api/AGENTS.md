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
  `/api/(.*)` catch-all, which sends everything else to MOTIS. `/metrics` also
  goes to MOTIS (realtime age and match rate).
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
  `/bus/<dataset>`; `build_index.py` runs at image build; `record.py` records
  live feeds as test fixtures and prints match rates. To add a feed (alerts,
  A1), add it to `adapter.py` and a `rt` entry to `config.yml`.
- `motis/smoke.sh`: smoke test against any base URL.

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

## Deploy

The project is linked to GitHub with Root Directory `apps/api`: pushes to a
branch build a preview, and merges to `main` deploy production. To deploy by
hand, run `vercel deploy --prod --scope charlespan-projects` from `apps/api/`.

## Environment variables

- `PORT`: port MOTIS listens on (container default `80`, Vercel's default).
- `MTA_BUS_TIME_KEY`: MTA Bus Time key, read by the adapter only (MOTIS never
  sees it). Without it, bus realtime is off and the bus feeds answer 404.
