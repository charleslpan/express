#!/usr/bin/env python3
"""Builds the app's bundled subway line geometry from the MTA's GTFS feed.

    python3 scripts/subway-lines/generate.py [path/to/gtfs_supplemented.zip]

With no argument it downloads the feed Express's MOTIS server imports (the MTA's own, from its GTFS bucket), reads
`routes.txt`, `trips.txt` and `shapes.txt`, and writes `apps/ios/App/Map/SubwayLines/subway-lines.json`.

Shapes of different routes run over the same track with the same vertices, so the script splits every shape into
edges (rounded to 1e-5 degrees, about a metre), notes which route colours use each edge, and chains the edges that
share a colour set back into polylines. Track that several colours share (the A and the F at Jackson Heights) is one
polyline with several colours; the app draws it as concentric stripes. Bus routes aren't in this feed's subway shapes
(only `route_type` 1 routes are read), and the Staten Island Railway (type 2) is left out.

The output is deterministic for a given feed and records the feed's version, dates, and SHA-256, so a changed file
means the MTA changed the feed. See scripts/subway-lines/README.md for provenance and terms. Standard library only.
"""

import csv
import hashlib
import io
import json
import sys
import urllib.request
import zipfile
from collections import defaultdict
from pathlib import Path

FEED_URL = "https://rrgtfsfeeds.s3.amazonaws.com/gtfs_supplemented.zip"
OUTPUT = Path(__file__).resolve().parents[2] / "apps/ios/App/Map/SubwayLines/subway-lines.json"
PRECISION = 5
SUBWAY_ROUTE_TYPE = "1"


def encode(points):
    """Google's encoded polyline format at PRECISION, from (lat, lon) integers already scaled by 10**PRECISION."""
    out = []
    last = (0, 0)
    for lat, lon in points:
        for delta in (lat - last[0], lon - last[1]):
            value = ~(delta << 1) if delta < 0 else delta << 1
            while value >= 0x20:
                out.append(chr((0x20 | (value & 0x1F)) + 63))
                value >>= 5
            out.append(chr(value + 63))
        last = (lat, lon)
    return "".join(out)


def read_rows(archive, name):
    with archive.open(name) as file:
        yield from csv.DictReader(io.TextIOWrapper(file, encoding="utf-8-sig"))


def main():
    if len(sys.argv) > 1:
        data = Path(sys.argv[1]).read_bytes()
    else:
        with urllib.request.urlopen(FEED_URL, timeout=120) as response:
            data = response.read()
    archive = zipfile.ZipFile(io.BytesIO(data))
    feed = next(read_rows(archive, "feed_info.txt"))

    routes = {}
    for row in read_rows(archive, "routes.txt"):
        if row["route_type"] == SUBWAY_ROUTE_TYPE:
            routes[row["route_id"]] = (int(row["route_sort_order"] or 0), row["route_color"].upper())

    shape_routes = defaultdict(set)
    for row in read_rows(archive, "trips.txt"):
        if row["route_id"] in routes:
            shape_routes[row["shape_id"]].add(row["route_id"])

    shapes = defaultdict(list)
    for row in read_rows(archive, "shapes.txt"):
        if row["shape_id"] in shape_routes:
            shapes[row["shape_id"]].append(
                (
                    int(row["shape_pt_sequence"]),
                    round(float(row["shape_pt_lat"]) * 10**PRECISION),
                    round(float(row["shape_pt_lon"]) * 10**PRECISION),
                )
            )

    # Each undirected edge between two vertices, with the route colours that run over it.
    edge_colors = defaultdict(set)
    for shape_id, points in shapes.items():
        vertices = [(lat, lon) for _, lat, lon in sorted(points)]
        colors = {routes[route][1] for route in shape_routes[shape_id]}
        for a, b in zip(vertices, vertices[1:]):
            if a != b:
                edge_colors[frozenset((a, b))].update(colors)

    # Order colours by the lowest sort order of the routes that use them, so stripes are stable.
    color_order = {}
    for order, color in sorted((order, color) for order, color in routes.values()):
        color_order.setdefault(color, order)

    by_colors = defaultdict(set)
    for edge, colors in edge_colors.items():
        by_colors[tuple(sorted(colors, key=lambda c: (color_order[c], c)))].add(edge)

    lines = []
    for colors, edges in by_colors.items():
        adjacency = defaultdict(set)
        for edge in edges:
            a, b = sorted(edge)
            adjacency[a].add(b)
            adjacency[b].add(a)
        unused = set(edges)

        def walk(start, first):
            chain = [start, first]
            unused.discard(frozenset((start, first)))
            while len(adjacency[chain[-1]]) == 2:
                nxt = [n for n in adjacency[chain[-1]] if frozenset((chain[-1], n)) in unused]
                if not nxt:
                    break
                unused.discard(frozenset((chain[-1], nxt[0])))
                chain.append(nxt[0])
            return chain

        # Chains start at vertices where the colour set's track ends or branches, then any loop that's left.
        for vertex in sorted(adjacency):
            if len(adjacency[vertex]) != 2:
                for neighbor in sorted(adjacency[vertex]):
                    if frozenset((vertex, neighbor)) in unused:
                        lines.append((colors, walk(vertex, neighbor)))
        for edge in sorted(unused, key=sorted):
            if edge in unused:
                a, b = sorted(edge)
                lines.append((colors, walk(a, b)))

    lines.sort(key=lambda line: (len(line[0]), line[0], line[1][0]))
    document = {
        "source": FEED_URL,
        "generator": "scripts/subway-lines/generate.py",
        "feedPublisher": feed["feed_publisher_name"],
        "feedVersion": feed["feed_version"],
        "feedStart": feed["feed_start_date"],
        "feedEnd": feed["feed_end_date"],
        "feedSHA256": hashlib.sha256(data).hexdigest(),
        "precision": PRECISION,
        "lines": [{"colors": list(colors), "path": encode(chain)} for colors, chain in lines],
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(document, separators=(",", ":")) + "\n")
    vertices = sum(len(chain) for _, chain in lines)
    print(f"{OUTPUT}: {len(lines)} lines, {vertices} vertices, {OUTPUT.stat().st_size} bytes", file=sys.stderr)


if __name__ == "__main__":
    main()
