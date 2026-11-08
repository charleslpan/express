"""Realtime feeds for MOTIS, served on localhost.

MOTIS polls this server (see config.yml); each poll fetches the upstream feed
once and answers with it corrected, so there is no timer here. The one
exception is the start: every feed is fetched at once, in parallel, and
MOTIS's first polls take those results (upstream.py).

- /subway/<feed>: an MTA subway feed with trip ids matched to the static
  timetable baked into the image (matcher.py).
- /bus/<dataset>: MTA Bus Time trip updates for one bus dataset. Bus Time is
  one fleet-wide feed and MOTIS fetches it once per bus dataset, so the six
  polls of a cycle share one upstream fetch, keeping to the MTA's limit of one
  fleet-wide call per 30 s, and each dataset gets only its own routes.
- /alerts/subway and /alerts/bus/<dataset>: the MTA's service alerts with the
  standard effect, cause, and severity filled from the MTA's alert type
  (alerts.py). The bus alerts feed is shared by the six bus polls the same way,
  and each dataset gets the alerts naming its routes.

To add a feed, add an entry to SUBWAY_FEEDS (or a handler for a new prefix)
and point a `rt` entry in config.yml at it.
"""

from __future__ import annotations

import json
import logging
import os
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from google.transit import gtfs_realtime_pb2

from alerts import AlertStats, AlertTypes, alerts_for_routes, fill_alerts
from matcher import FeedStats, Timetable, rewrite_feed
from upstream import Upstream

MTA = "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2F"
SUBWAY_FEEDS = {
    name: MTA + name
    for name in ("gtfs", "gtfs-ace", "gtfs-bdfm", "gtfs-g", "gtfs-jz",
                 "gtfs-nqrw", "gtfs-l", "gtfs-si")
}
BUS_TIME = "https://gtfsrt.prod.obanyc.com/tripUpdates"
# The MTA's alert feeds, with no key.
ALERT_FEEDS = {
    "subway": "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/camsys%2Fsubway-alerts",
    "bus": "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/camsys%2Fbus-alerts",
}
BUS_MIN_INTERVAL = 25  # s; MOTIS polls every 30 s, all datasets at once
TIMEOUT = 10  # s, below MOTIS's own http_timeout

log = logging.getLogger("adapter")


def fetch(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "express-motis-adapter"})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
        return r.read()


class Subway:
    def __init__(self, tt: Timetable, upstream: Upstream):
        self.tt = tt
        self.upstream = upstream

    def get(self, name: str) -> bytes | None:
        url = SUBWAY_FEEDS.get(name)
        if url is None:
            return None
        feed = gtfs_realtime_pb2.FeedMessage()
        feed.ParseFromString(self.upstream.get(url))
        s = rewrite_feed(feed, self.tt)
        log.info("subway %s: %s", name, _describe(s, feed.header.timestamp))
        return feed.SerializeToString()


class Bus:
    def __init__(self, key: str, routes: dict[str, list[str]], upstream: Upstream):
        self.key = key
        self.upstream = upstream
        self.routes = {d: set(r) for d, r in routes.items()}
        self._lock = threading.Lock()
        self._feed: gtfs_realtime_pb2.FeedMessage | None = None
        self._at = 0.0

    def get(self, dataset: str) -> bytes | None:
        routes = self.routes.get(dataset)
        if routes is None or not self.key:
            return None
        whole = self._fleet()
        out = gtfs_realtime_pb2.FeedMessage()
        out.header.CopyFrom(whole.header)
        out.entity.extend(
            e for e in whole.entity
            if e.HasField("trip_update") and e.trip_update.trip.route_id in routes
        )
        return out.SerializeToString()

    def _fleet(self) -> gtfs_realtime_pb2.FeedMessage:
        with self._lock:
            if self._feed is None or time.monotonic() - self._at >= BUS_MIN_INTERVAL:
                feed = gtfs_realtime_pb2.FeedMessage()
                feed.ParseFromString(self.upstream.get(f"{BUS_TIME}?key={self.key}"))
                self._feed, self._at = feed, time.monotonic()
                n = sum(1 for e in feed.entity if e.HasField("trip_update"))
                known = set().union(*self.routes.values())
                ours = sum(1 for e in feed.entity if e.HasField("trip_update")
                           and e.trip_update.trip.route_id in known)
                log.info("bus: %d trip updates, %d on loaded routes, feed age %s",
                         n, ours, _age(feed.header.timestamp))
            return self._feed


class Alerts:
    def __init__(self, types: AlertTypes, bus_routes: dict[str, list[str]], upstream: Upstream):
        self.types = types
        self.upstream = upstream
        self.bus_routes = {d: set(r) for d, r in bus_routes.items()}
        self._lock = threading.Lock()
        self._bus: gtfs_realtime_pb2.FeedMessage | None = None
        self._bus_at = 0.0
        self._warned: set[str] = set()

    def get(self, name: str) -> bytes | None:
        if name == "subway":
            return self._load("subway").SerializeToString()
        kind, _, dataset = name.partition("/")
        routes = self.bus_routes.get(dataset)
        if kind != "bus" or routes is None:
            return None
        with self._lock:
            if self._bus is None or time.monotonic() - self._bus_at >= BUS_MIN_INTERVAL:
                self._bus, self._bus_at = self._load("bus"), time.monotonic()
            feed = self._bus
        return alerts_for_routes(feed, routes).SerializeToString()

    def _load(self, kind: str) -> gtfs_realtime_pb2.FeedMessage:
        feed = gtfs_realtime_pb2.FeedMessage()
        feed.ParseFromString(self.upstream.get(ALERT_FEEDS[kind]))
        s = fill_alerts(feed, self.types)
        log.info("alerts %s: %s", kind, self._summary(s, feed.header.timestamp))
        return feed

    def _summary(self, s: AlertStats, ts: int) -> str:
        new = sorted(set(s.unknown) - self._warned)
        if new:  # once per type, not every poll
            self._warned.update(new)
            log.warning("unknown MTA alert types (mapped to the fallback): %s", ", ".join(new))
        unknown = sum(s.unknown.values())
        return f"{s.alerts} alerts, {unknown} of unknown type, feed age {_age(ts)}"


def _describe(s: FeedStats, ts: int) -> str:
    pct = 100 * s.matched / s.trip_updates if s.trip_updates else 0
    return (f"{s.trip_updates} trip updates, {s.matched} matched ({pct:.1f}%), "
            f"{s.added} added, {s.dropped} dropped, feed age {_age(ts)}")


def _age(ts: int) -> str:
    return f"{time.time() - ts:.0f}s" if ts else "unknown"


def make_handler(subway: Subway, bus: Bus, alerts: Alerts):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            kind, _, name = self.path.lstrip("/").partition("/")
            source = {"subway": subway, "bus": bus, "alerts": alerts}.get(kind)
            try:
                body = source.get(name) if source else None
            except Exception as e:  # upstream down or bad bytes
                log.warning("%s: %s", self.path, e)
                self.send_error(502)
                return
            if body is None:
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header("Content-Type", "application/x-protobuf")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass  # one line per feed from the sources is enough

    return Handler


def main():
    logging.basicConfig(level=logging.INFO, format="%(asctime)s [adapter] %(message)s")
    here = os.environ.get("ADAPTER_DATA", "/srv/adapter")
    t = time.monotonic()
    key = os.environ.get("MTA_BUS_TIME_KEY", "")
    if not key:
        log.warning("MTA_BUS_TIME_KEY is not set: bus feeds answer 404")
    # Fetch every feed at once, first thing, while the index and then MOTIS
    # load: MOTIS's first cycle takes these instead of fetching feed after
    # feed, so it turns healthy sooner (upstream.py).
    upstream = Upstream(fetch)
    upstream.start([*SUBWAY_FEEDS.values(), *ALERT_FEEDS.values(), *([f"{BUS_TIME}?key={key}"] if key else [])])
    tt = Timetable.load(os.path.join(here, "subway_index.json"))
    with open(os.path.join(here, "bus_routes.json")) as f:
        bus_routes = json.load(f)
    port = int(os.environ.get("ADAPTER_PORT", "8081"))
    server = ThreadingHTTPServer(
        ("127.0.0.1", port),
        make_handler(Subway(tt, upstream), Bus(key, bus_routes, upstream),
                     Alerts(AlertTypes.load(os.path.join(here, "alert_types.json")), bus_routes, upstream)),
    )
    log.info("listening on 127.0.0.1:%d (index loaded in %.1fs)", port, time.monotonic() - t)
    # The entrypoint starts MOTIS once this file exists.
    open(os.environ.get("ADAPTER_READY", "/tmp/adapter.ready"), "w").close()
    server.serve_forever()


if __name__ == "__main__":
    main()
