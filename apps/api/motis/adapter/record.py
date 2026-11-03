"""Record the live subway feeds and report how many trips match.

Usage: record.py <subway_index.json> [<out dir>]

Prints matched / added / dropped per feed. With an out dir, saves each feed
as <feed>.pb.gz (test fixtures) plus timetable.json, the part of the index
those feeds need (trips within 30 minutes of a live train, on its start date
and the day before), so tests run without the full timetable.
"""

import gzip
import json
import os
import sys

from google.transit import gtfs_realtime_pb2

from adapter import SUBWAY_FEEDS, fetch
from matcher import DAY, FeedStats, Timetable, _shift, parse_trip_id, rewrite_feed

NEAR = 3000  # 30 minutes in 1/100 minute


def main(index_path: str, out: str | None = None) -> None:
    with open(index_path) as f:
        index = json.load(f)
    tt = Timetable.from_index(index)
    total, live, dates = FeedStats(), [], set()
    print(f"{'feed':<10} {'trips':>6} {'matched':>8} {'added':>6} {'dropped':>8}")
    for name, url in SUBWAY_FEEDS.items():
        raw = fetch(url)
        feed = gtfs_realtime_pb2.FeedMessage()
        feed.ParseFromString(raw)
        for e in feed.entity:
            k = parse_trip_id(e.trip_update.trip.trip_id)
            if k and e.trip_update.trip.start_date:
                live.append(k)
                d = e.trip_update.trip.start_date
                dates.update((d, _shift(d, -1)))
        s = rewrite_feed(feed, tt)
        total += s
        print(f"{name:<10} {s.trip_updates:>6} {s.matched:>8} {s.added:>6} {s.dropped:>8}")
        if out:
            with gzip.open(os.path.join(out, f"{name}.pb.gz"), "wb") as f:
                f.write(raw)
    pct = 100 * total.matched / total.trip_updates if total.trip_updates else 0
    print(f"{'all':<10} {total.trip_updates:>6} {total.matched:>8} {total.added:>6} "
          f"{total.dropped:>8}  ({pct:.1f}% matched)")
    if out:
        def near(k):
            return any(
                k.route == r.route and k.direction == r.direction
                and min(abs(k.origin - r.origin), abs(k.origin - r.origin - DAY)) <= NEAR
                for r in live
            )

        services = {s: sorted(dates.intersection(d))
                    for s, d in index["services"].items() if dates.intersection(d)}
        trips = [t for t in index["trips"]
                 if t[1] in services and (k := parse_trip_id(t[0])) and near(k)]
        with open(os.path.join(out, "timetable.json"), "w") as f:
            json.dump({
                "routes": index["routes"],
                "stops": index["stops"],
                "services": {s: services[s] for s in {t[1] for t in trips}},
                "trips": trips,
            }, f, separators=(",", ":"))


if __name__ == "__main__":
    main(*sys.argv[1:])
