# Platform, exit and transfer-position data for NYC subway riders

Research note, accessed 2026-11-25/26. Nothing here is implemented in the app. Claims are marked
**VERIFIED** (I fetched or queried the primary source myself) or **UNVERIFIED** (reported by a
secondary source, or a page I could not fetch). Raw downloads were kept out of the repo.

## TL;DR

| Question | Answer |
| --- | --- |
| Is there an official, reusable "which car to board" dataset for the NYC subway? | **No.** MTA publishes none (VERIFIED: no such field in any MTA open dataset or GTFS feed I inspected). |
| Do commercial apps have it? | **Yes, as UI only.** Exit Strategy NYC (hand-surveyed, paid app) and Citymapper (front/middle/back) show it. Neither documents an API, dataset or reuse license. |
| Any open, structured, reusable per-station car data? | **Barely.** OpenStreetMap has an in-draft tag, `exit:carriages`; NYC has it on **12 stop nodes covering about 5 stations** (of ~496). A downstream open API (exits.to) republishes those 5. |
| GTFS pathways / station indoor graph from MTA? | **No.** The subway feed has `transfers.txt` (min times) and no `pathways.txt` or `levels.txt`. LIRR, Metro-North and the bus feeds have none either (VERIFIED). |
| Street entrances/exits as data? | **Yes.** MTA open data, 2,120 rows, with coordinates and entrance type but **no platform or car position** (VERIFIED). |
| Elevator/escalator and ADA data? | **Yes**, and it carries free-text notes plus some mezzanine/platform fields (VERIFIED). Accessibility only, not car position. |
| Platform and entrance geometry? | **Partly, in OSM.** Entrances and platform polygons are mapped broadly; platform-to-street footway connectivity is patchy (VERIFIED by Overpass sampling). |
| Public discussion? | Old (2009 to 2021) and thin: app launch threads and reviews. No crowdsourced NYC dataset effort found. |

## Findings table

| Source | What it is | Owner | License / terms | Access | Verified? | Coverage |
| --- | --- | --- | --- | --- | --- | --- |
| Exit Strategy NYC | Per-station "where to stand" diagrams: exits, transfers, elevators, often to the door | JWeg Ventures LLC (App Store seller) | Closed. Listing says "All subway, bus, and street maps are property of the MTA." No API or terms found | UI only (iPhone, $3.99) | VERIFIED listing + site; data itself not inspected | Site claims "all 469 subway stops" |
| Citymapper | "Best section" (Front/Middle/Back), best entrance/exit | Citymapper | No reuse terms found | UI only | VERIFIED pages; coverage UNVERIFIED | "Collected as much as we've been able to ... not complete" |
| Transit app | Crowdsourced "best station exits" (no car feature found) | Transit | None found | UI only | VERIFIED App Store text | Unknown |
| Google Maps / Apple Maps / Moovit | Entrance/exit guidance; Google "boarding position" reported in Zurich only | Respective vendors | Proprietary | UI only | Mostly UNVERIFIED (secondary articles) | Unknown for NYC |
| MTA Subway Entrances and Exits: 2024 (`i9wp-a4ja`) | Every entrance/exit with lat/lon and type | MTA | OPEN-NY terms; per-dataset license field empty | SODA API, CSV, JSON | VERIFIED | 2,120 rows |
| MTA Subway Stations (`39hk-dx4f`) / Stations and Complexes (`5f5g-n3cz`) | Station and complex list, ADA flags, direction labels | MTA | same | SODA API | VERIFIED | 496 / 445 rows |
| MTA Elevator/Escalator Asset Inventory (`94fv-bak7`) | Per-asset inventory with free-text `notes`, platform/mezzanine access fields | MTA | same | SODA API | VERIFIED | 759 rows |
| MTA static GTFS (subway, LIRR, MNR, bus) | Schedules, `transfers.txt` | MTA | "Our data feeds are free to use"; logos/maps/IP need a license | Zip on S3 | VERIFIED | Subway: 496 parent stations, 613 transfer rows |
| OpenStreetMap | Entrances, platforms, footways, stop areas, `exit:carriages` | OSM contributors | ODbL 1.0 | Overpass API, planet extracts | VERIFIED | See below |
| exits.to / k-yle/subway-exit-map | App + JSON API built on OSM `exit:carriages` | Individual (GitHub k-yle) | Code MIT; data ODbL (OSM) + CC0 (Wikidata) | `api.json` over HTTPS | VERIFIED | 5 NYC stations of 475 worldwide |

## 1. Apps and sites (UI versus data)

**Exit Strategy NYC.** Seller JWeg Ventures LLC; iPhone only, $3.99; v2.97 listed as updated 14 Oct
(year not shown); 4.8 stars from 197 ratings. The listing describes "exit diagrams that show where to
stand on a train, including exits, transfer points, and elevators, in many cases down to the door",
works offline, and says "The developer does not collect any data from this app" (unverified by
Apple). Version notes mention "over 100 station diagrams" updated in 2024 and "changed the G train
to 8 cars", so the data is hand-maintained per train length.
Source: https://apps.apple.com/app/id320946370 and http://www.exitstrategynyc.com/ (VERIFIED, 2026-11-26).
Origin: Second Avenue Sagas (2009-07-07, Benjamin Kabak) reports the founders, a sibling pair, gathered
the data by standing in stations and watching which doors lined up with exits; the same piece notes
car lengths forced updates when the F changed models (https://secondavenuesagas.com/2009/07/07/a-mobile-cheat-sheet-for-subway-exits/).
The app site has no license, terms or API (VERIFIED). **Conclusion: proprietary survey data, UI only.**
Reusing it would mean extracting from a paid app, which this research did not attempt.

**Citymapper.** Its own posts say it shows "where to board the train (Front, Middle or Back) so you can be
close to the exit" and "the best entrance or exit" (https://citymapper.com/news/777/10-citymapper-tools-to-help-you-master-new-york),
and "We have collected this data as much as we've been able to in all our cities, but its not complete"
with an in-app "Improve Data" option (https://citymapper.com/news/726/where-to-get-on-the-train).
Also "best section" for all PATH stations (https://citymapper.com/news/2679/best-train-section-now-available-for-all-path-stations).
None of these pages is dated; none mentions an API or reuse license (VERIFIED). UI only.

**Transit app.** App Store text: "See what millions of riders say about crowding levels, on-time
performance, the best station exits, and more." No car feature on the page (https://apps.apple.com/app/transit/id498151501, VERIFIED).

**Google Maps, Apple Maps, Moovit.** Secondary articles say Google shows a "boarding position for
fastest exit" on some Zurich S-Bahn trips, Apple Maps and Moovit show entrance/exit guidance; I found
no official page confirming any of them for NYC subway cars. UNVERIFIED.

## 2. MTA and open government data

All queried live through data.ny.gov SODA (`https://data.ny.gov/resource/<id>.json`) on 2026-11-26.

**MTA Subway Entrances and Exits: 2024** (`i9wp-a4ja`). Owner MTA/NYC Transit, "Static - Not Updated"
(time period 2024; metadata last touched 2025-12-05), 2,120 rows, license field empty (data.ny.gov
OPEN-NY terms apply). Columns: `division, line, borough, stop_name, complex_id,
constituent_station_name, station_id, gtfs_stop_id, daytime_routes, entrance_type, entry_allowed,
exit_allowed, entrance_latitude, entrance_longitude, entrance_georeference`. **No platform, car,
level or street-name field.** Entrance types: Stair 1629, Easement-Street 164, Station House 112,
Elevator 102, Easement-Passage 57, Escalator 18, other 38.
```json
{"stop_name":"Times Sq-42 St/Port Authority Bus Terminal","complex_id":"611","constituent_station_name":"Times Sq-42 St","station_id":"11","gtfs_stop_id":"R16","entrance_type":"Stair","entry_allowed":"YES","exit_allowed":"YES","entrance_latitude":"40.7545181","entrance_longitude":"-73.9871143"}
{"stop_name":"Atlantic Av-Barclays Ctr","complex_id":"617","gtfs_stop_id":"R31","entrance_type":"Elevator","entrance_latitude":"40.683805","entrance_longitude":"-73.978487"}
```
Times Sq-42 St complex 611 has 28 rows; Atlantic Av-Barclays Ctr 9; Marcy Av 8.

**Stations** (`39hk-dx4f`, 496 rows): `gtfs_stop_id, station_id, complex_id, division, line, stop_name,
borough, cbd, daytime_routes, structure, gtfs_latitude/longitude, north_direction_label,
south_direction_label, ada, ada_northbound, ada_southbound, ada_notes`. **Stations and Complexes**
(`5f5g-n3cz`, 445 rows): `complex_id, is_complex, number_of_stations_in_complex, display_name,
constituent_station_names, station_ids, gtfs_stop_ids, structure_type, ada, ada_notes...`. Updated 2026-11-25.
Times Sq row: `complex_id 611, 5 constituent stations, gtfs_stop_ids "127; 725; 902; A27; R16", ada 1`.

**Elevator/Escalator Asset Inventory** (`94fv-bak7`, 759 rows, daily): has `station_complex_mrn`,
coordinates, `elevator_direction_serviced`, `elevator_mezzanine_1_access`, `elevator_platform_access`
and free text `notes`, e.g. escalator ES218: "7 platform to upper mezzanine for 41 St & 7 Ave exit and
access to rest of complex". It is the closest thing to a "where does this connect" record, but only
for lifts and escalators, only in prose. Availability history (`rc78-7x78`, 84,474 rows, monthly) is
uptime only.

**GTFS static.** Feeds listed at https://www.mta.info/developers (subway, supplemented subway, LIRR, MNR,
five borough bus feeds, MTA Bus Co; Pascack Valley/Port Jervis via NJ TRANSIT). I downloaded subway, supplemented
subway, LIRR, MNR, Bus Co and Staten Island bus (VERIFIED):
- **No `pathways.txt` or `levels.txt` in any of them.**
- Subway feed `20261028-fall-2026-pick-with-long-term-supplements`, valid 2026-11-01 to 2027-05-15: stops.txt has 1,488 rows (496 parent stations, 992 platform stops, no `wheelchair_boarding` column);
  transfers.txt has 613 rows, all `transfer_type=2` with `min_transfer_time`: 180 s x504, 0 s x59, 300 s x40, 420 s x4, 90 s x4, 240 s x2; 150 rows connect different stops (complex transfers).
- LIRR transfers.txt: 244 rows; MNR: 14,817 trip-to-trip transfers (`transfer_type=1`). LIRR stops.txt has `wheelchair_boarding` for 127 stops.
- PATH and NJ TRANSIT feeds: **UNVERIFIED**. I could not fetch PANYNJ (TLS error) or Transitland (403); NJT requires a developer login, which I did not create.

**Terms.** MTA developer page (WebFetch of https://www.mta.info/developers, 2026-11-26; direct curl got 403):
"Our data feeds are free to use." and "to use our logos, maps, symbols or other intellectual property,
you need to apply for a license." MTA-approved free apps need a license with no fee; commercial or
ad-sponsored apps "may be charged a license fee." No redistribution terms are given for GTFS files. MTA maps
(including neighborhood maps, which Exit Strategy builds on) are MTA IP. data.ny.gov datasets fall
under the OPEN-NY Terms of Use (https://data.ny.gov/download/77gx-ii52/application/pdf); I could not
read the PDF (signed redirect), so its attribution/indemnity wording is UNVERIFIED (a Reinvent Albany
summary says no attribution/share-alike and an indemnification clause).

**Official station maps.** (Search-result summaries of MTA pages, not fetched: UNVERIFIED.) MTA's accessibility pages describe on-station "Accessible Pathway Diagrams"
and alternate-route maps at elevators (tested at Jay St-MetroTech) and PDF/digital system and
neighborhood maps (https://www.mta.info/accessibility/innovations/stationlab/how-we-set-up,
https://www.mta.info/maps/subway). These are images/PDFs on signs and pages, not data. I found no
machine-readable station layout and no MTA indoor-map dataset (search only, UNVERIFIED as absence).

## 3. OpenStreetMap

Overpass API (https://overpass-api.de/api/interpreter, base timestamp 2026-11-26T02:27Z), area =
City of New York (admin_level 5). All counts VERIFIED.

**NYC-wide:**

| Feature | Count |
| --- | --- |
| `railway=subway_entrance` nodes | 2,026 (MTA open data: 2,120 incl. SIR) |
| ...with `name` | 249 |
| ...with `ref` | 6 |
| ...with `level` | 1,965 |
| ...with `wheelchair` | 1,997 |
| ...with `entrance=*` / `door=*` / `elevator=*` / `exit_to=*` | 79 / 46 / 4 / 0 |
| ...that are a member of any way (i.e. connected to a path) | 851 (395 on `highway=steps`) |
| `railway=stop` nodes, network "NYC Subway" | 1,105 (`public_transport=stop_position` + `subway=yes`: 1,201) |
| Platforms (`public_transport=platform`, `subway=yes`), mostly ways | 960 (916 carry `level`) |
| Footway/steps/corridor/elevator ways touching a subway platform polygon | 168 |
| Footway/steps/corridor ways with `tunnel=yes` | 694 (520 also with `level`) |
| `stop_area` relations, network NYC Subway | 553 (a further 4 `stop_area_group`) |
| `railway=station`+`station=subway` | 499 |
| **Nodes with `exit:carriages*` or `destination:carriages*`** | **12** |

Entrances are mostly an MTA-derived import: little naming, a `description` of the routes served and
`wheelchair`, and `ref` almost never. Sample entrance (Union Sq):
```json
{"railway":"subway_entrance","level":"0","description":"all 4,5,6,<6>,L,N,Q,R,W trains","wheelchair":"no","network":"NYC Subway"}
```
Sample platform (Atlantic Av-Barclays, way):
```json
{"public_transport":"platform","railway":"platform","subway":"yes","level":"-3","layer":"-3","location":"underground","gtfs:stop_id":"D24N;D24S","name":"Atlantic Avenue - Barclays Center (B,Q)","wheelchair":"yes"}
```

**Station samples** (nodes/ways within 150-300 m of the station, so neighbors leak in; counts are
OSM-only and approximate):

| Station | Entrances in OSM (MTA rows) | Platform ways | Tunnel footway/steps/elevator ways | Touch an entrance node | Touch a platform polygon |
| --- | --- | --- | --- | --- | --- |
| Times Sq-42 St | 29 (28) | 10 | 56 (48 steps, 5 elevator, 3 footway) | 15 | 2 |
| 14 St-Union Sq | 13 (12) | 5 | 37 | 8 | 0 |
| Atlantic Av-Barclays | 5 (9) | 6 | 49 | 3 | 0 |
| Marcy Av (J/M/Z) | 8 (8) | 2 | 0 | 0 | 0 |

So geometry and entrances exist, but a routable platform-to-street path (platform to mezzanine to
stair to street) is **not** reliably there: Union Sq, Atlantic and Marcy show no linked footway at the
platform. Entrance completeness varies (Atlantic: 5 in OSM vs 9 official). None of the four stations
has `exit:carriages`.

**Car-position tags.** The OSM wiki's "Proposal:Platform exits" (draft, started 2024-02-13 by Kylenz; no
vote recorded) defines `exit:carriages[:forward|:backward]`, `destination:carriages`,
`destination:ref:carriages` on `public_transport=stop_position`, values like `no|no|stairs|stairs;lift`,
ordered from the train front. It says NYC apps use proprietary data and notes the tag set is limited
(https://wiki.openstreetmap.org/wiki/Proposal:Platform_exits, talk page has no NYC mention and no
copyright discussion). Taginfo (2026-11-26): `exit:carriages:forward` 1,227 nodes worldwide,
`:backward` 63, bare `exit:carriages` 16.

NYC stop nodes with the tags (12; all `public_transport=stop_position`):
Queensboro Plaza x4 (upper and lower levels), 33rd St-Rawson St x2 (7), 145th St x2 (3), Harlem-148th St x2 (3), Howard Beach-JFK x2 (A).
```json
{"name":"33rd Street–Rawson Street","public_transport":"stop_position","railway":"stop","side":"right",
 "exit:carriages":"no|no|no|stairs|no|stairs|no|no|stairs|no|stairs",
 "destination:carriages":"none|none|none|34th St|none|34th St|none|none|33rd St|none|33rd St"}
```
That is roughly 5 of ~496 stations (1%).

**Downstream API.** exits.to is the demo of https://github.com/k-yle/subway-exit-map (MIT; created 2024-05-06, last
push 2026-11-05, 2 stars). Its `https://kyle.kiwi/subway-exit-map/api.json` (4.9 MB, generated
2026-11-13) holds 475 stations across 16 networks; **5 are "New York City Subway"**. README: data is
ODbL (OSM) plus CC0 (Wikidata). Per-carriage record excerpt: `{"type":"middle","ref":4,"isBest":true,"exitType":["stairs"],"exitTo":["34th St"]}` (VERIFIED).

**ODbL implications (one line each).** Attribution to OpenStreetMap contributors is required wherever the
data is shown. Share-alike applies to a derived *database*; produced works (e.g. a rendered map or a
"best car" answer) only need attribution, and an app that queries OSM without redistributing a derivative
database is generally fine, but adding our own data into an OSM-derived database triggers share-alike for that database
(legal reading, not legal advice). The OSM wiki itself is CC BY-SA 2.0.

## 4. Community discussion (direct, attributable only)

- Hacker News, 2009-07-07, "Review my app: For you NYC Hackers/Subway Riders" (Exit Strategy launch, posted by bdotdub, 100 points):
  commenters praise it; one (jakewolf) asks not to tell anyone; another (vincent_vega) asks whether it "will lead to everyone standing
  at the same positions" and whether one can simply build it oneself. https://news.ycombinator.com/item?id=692351 (VERIFIED via HN Algolia API).
- Second Avenue Sagas comment, 2021-01-23: the Exit Strategy app lacked Second Avenue Q layouts and had missing or unclear
  elevator/escalator locations (VERIFIED, same URL as above; commenter unnamed here).
- NYC Transit Forums, "Tips for exits at subway stations" (https://www.nyctransitforums.com/topic/45116-tips-for-exits-at-subway-stations/) and
  "illegal subway signs show commuters how to nail the transfer" (https://www.nyctransitforums.com/topic/44170-illegal-subway-signs-show-commuters-how-to-nail-the-transfer/): UNVERIFIED. The site returned 403
  to my fetches; I only have a search-engine summary (one poster says MTA once gave more specific car guidance, then dropped it because riders crowded the nearest car).
- OSM Proposal talk page, 2024-02-11 to 2024-03-12 (Kylenz, Kovposch): says surveying where trains stop is impractical underground, so tagging
  is by carriage index. No NYC mention (VERIFIED).
- Hacker News 2026-03-29 "Show HN: Public transit systems as data" (https://news.ycombinator.com/item?id=47561132, qwertykb): lists NYC (472 stations) but I saw no exit or
  car data on the site (VERIFIED homepage).
- Reddit (r/nyc, r/nycrail, r/NYCTransit): **could not search**; Reddit returned 403 and the web-search tool returned no Reddit threads. No claim made.
- GitHub: searches and `api.github.com` found no repo with NYC car-position or exit-to-car data other than the OSM-derived exits.to project. The MTA
  has said subway cars (unlike LIRR/MNR) lack car-load sensing (mta.info article, via search, UNVERIFIED).

## 5. Implications for the app (not a design)

1. **No ready dataset.** Best-car answers for NYC are proprietary or hand-surveyed; the open route is OSM's `exit:carriages`, which today covers ~1% of stations.
2. **What can be derived from public data:** entrance coordinates and type (MTA), platform polygons with level and often `gtfs:stop_id` (OSM), parent/child stops and direction labels (GTFS, MTA stations), transfer minimum times (GTFS), lifts and prose connection notes (MTA asset inventory).
3. **What is missing:** the link between a platform position and an exit (stair or escalator foot on the platform), per-line train length (8/10/11 cars varies by line and changes, e.g. G), where each train stops relative to the platform ends (not surveyable underground per OSM discussion), mezzanine-level paths, and which street exit leads where. A geometric guess (project the nearest platform-connected stair to a platform axis and map it to the front/middle/back third) would need those stairs to be mapped, and OSM has linked footways at the platform at few of the stations sampled.
4. **Honest options:** (a) show nothing; (b) show a coarse "front/middle/back" only where OSM `exit:carriages` or a hand-built table exists, with attribution; (c) fund a survey, possibly seeding the OSM tag so it stays open. Any option should state its coverage.
5. **Licensing risk:** do not scrape Exit Strategy or Citymapper. Using MTA-published maps/diagrams needs an MTA license; MTA open data and GTFS are free to use but the OPEN-NY terms were not read in full.

## 6. Not found or could not verify

- Reddit threads about car/exit choice; NYC Transit Forums content (403).
- Any MTA dataset with platform exit or car position, or MTA GTFS pathways: none found in feeds I inspected. PATH and NJT feeds were not inspected.
- Official Google/Apple/Moovit documentation of a NYC car-position feature; their data provenance.
- Exit Strategy's data coverage, accuracy and terms of service beyond the App Store listing and site; Citymapper's NYC coverage figures.
- OPEN-NY Terms of Use full text; the older "NYC Transit Subway Entrance and Exit Data" dataset (listed on catalog.data.gov, not inspected).
- Whether exit nodes in OSM Queensboro/Howard Beach are accurate (not field-checked).
- Entrance `level` values distribution in OSM (1,965 tagged; only samples read, values like `0` and `0;1`).
