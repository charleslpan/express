# Subway lines

`generate.py` builds `apps/ios/App/Map/SubwayLines/subway-lines.json`, the static subway track the map draws
(`App/Map/SubwayLines.swift`, `SubwayLinesOverlay.swift`). No backend, network call, or API key is involved at
runtime.

## Source

The MTA's own static GTFS feed for the subway, `https://rrgtfsfeeds.s3.amazonaws.com/gtfs_supplemented.zip`
(published by MTA New York City Transit through [mta.info/developers](https://www.mta.info/developers)). It is the
same file `apps/api/motis/Dockerfile` imports into MOTIS, so the lines match the timetable, the bullets (route
colours come from `routes.txt`), and the live trains.

The URL is a moving target (the MTA replaces the file with each service change), so the generated JSON records the
feed's `feed_version`, start and end dates, and the SHA-256 of the exact zip it was built from. `generate.py` takes a
local zip as its argument to rebuild from a saved copy.

Only `routes.txt` rows with `route_type` 1 (subway) and the shapes their trips use are read; bus routes and the Staten
Island Railway aren't in the asset.

## Terms

The MTA's [developer terms and conditions](https://www.mta.info/developers/terms-and-conditions) make its data feeds
free to use; its logos, maps, and symbols are licensed separately. The asset is coordinates and the colour codes the
feed publishes, drawn by Express, not the MTA's map artwork or logos. Per the terms, the app must not state or imply
that the MTA licenses it or that the data is accurate, complete, or timely; it may say the data comes from the MTA.

## Refresh

```sh
python3 scripts/subway-lines/generate.py     # downloads the current feed
git diff --stat apps/ios/App/Map/SubwayLines
```

Commit the result when `feedVersion` changes and the lines moved (a new pick often changes nothing but the version).
