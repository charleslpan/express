"""Build the adapter's startup indexes from the GTFS zips MOTIS imports.

Usage: build_index.py <out dir> <subway gtfs.zip> <dataset>=<bus gtfs.zip>...

Runs at image build time on exactly the files MOTIS imports, so the adapter
matches against the timetable MOTIS loaded, never a fresher download.
"""

import csv
import io
import json
import os
import sys
import zipfile

from matcher import Timetable


def route_ids(path: str) -> list[str]:
    """Routes with trips in this feed. The five NYCT bus feeds share one
    routes.txt, but each borough's trips run on routes of their own."""
    with zipfile.ZipFile(path) as z:
        rows = csv.DictReader(io.TextIOWrapper(z.open("trips.txt"), "utf-8-sig"))
        return sorted({r["route_id"] for r in rows})


def main(out: str, subway: str, *buses: str) -> None:
    with open(os.path.join(out, "subway_index.json"), "w") as f:
        json.dump(Timetable.index_gtfs_zip(subway), f, separators=(",", ":"))
    routes = {}
    for arg in buses:
        dataset, _, path = arg.partition("=")
        routes[dataset] = route_ids(path)
    with open(os.path.join(out, "bus_routes.json"), "w") as f:
        json.dump(routes, f, indent=1)


if __name__ == "__main__":
    main(*sys.argv[1:])
