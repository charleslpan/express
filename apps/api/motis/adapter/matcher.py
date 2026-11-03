"""Match NYC subway GTFS-realtime trips to the static timetable.

MTA subway realtime trip ids ("071900_A..S58R") are not the static GTFS trip
ids ("BFA26GEN-A047-Weekday-00_071900_A..S58R"), and MOTIS resolves realtime
updates by trip id only. This module rewrites each realtime trip to the one
static trip it describes, following the MTA's "GTFS-realtime Reference for
the New York City Subway": normalise the dots, then match route, direction,
origin time, and start date, and use the path to break ties when the feed
sends one.

A live train no scheduled trip matches is sent as an ADDED trip with its own
stop times, never moved onto the nearest scheduled trip.

Self-contained on purpose: delete it if MOTIS ever matches NYC trips itself.
"""

from __future__ import annotations

import csv
import datetime as dt
import io
import json
import math
import re
import zipfile
from collections import defaultdict
from dataclasses import dataclass

from google.transit import gtfs_realtime_pb2

# <origin time in 1/100 min>_<route>.<dots><N|S><path>, with a
# "<schedule>_" prefix in the static feed.
_ID = re.compile(r"^(?:.*_)?(\d{6})_([A-Z0-9]+)\.+([NS])([A-Z0-9]*)$")

# Realtime route tokens that the static ids spell differently. W trains carry
# N ids in both feeds, so the id's own token is the key, never route_id.
ROUTE_ALIASES = {"6X": "6", "7X": "7", "FX": "F", "SS": "SI"}

DAY = 144000  # one day in 1/100 minute
MAX_SPEED = 100  # m/s; MOTIS drops an added trip that implies more

TripDescriptor = gtfs_realtime_pb2.TripDescriptor


@dataclass(frozen=True)
class TripKey:
    route: str
    direction: str
    origin: int  # 1/100 minute after the service day's midnight
    path: str


def parse_trip_id(trip_id: str) -> TripKey | None:
    m = _ID.match(trip_id)
    if not m:
        return None
    origin, route, direction, path = m.groups()
    return TripKey(ROUTE_ALIASES.get(route, route), direction, int(origin), path)


@dataclass(frozen=True)
class Match:
    trip_id: str
    start_date: str  # service day, YYYYMMDD
    start_time: str  # first departure as in stop_times.txt, may be >= 24:00


class Timetable:
    """The static subway trips, by route, direction, and origin time."""

    def __init__(self, trips, services, routes=(), stops=None):
        # trips: [(trip_id, service_id, first departure)]
        # services: {service_id: [YYYYMMDD]}
        # stops: {stop_id: (lat, lon)}
        self.routes = set(routes)
        self.stops = dict(stops or {})
        self._services = {s: frozenset(d) for s, d in services.items()}
        self._trips: dict[tuple, list] = defaultdict(list)
        for trip_id, service_id, start in trips:
            k = parse_trip_id(trip_id)
            if k is not None:
                self._trips[(k.route, k.direction, k.origin)].append(
                    (trip_id, k.path, service_id, start)
                )

    def match(self, trip_id: str, start_date: str) -> Match | None:
        """The one static trip a realtime trip runs as, or None.

        Exactly one candidate must remain; a near miss in time is never a
        match, so one train's countdown never lands on another.
        """
        k = parse_trip_id(trip_id)
        if k is None or not start_date:
            return None
        day, cands = start_date, self._running(k, k.origin, start_date)
        if not cands and k.origin < DAY:
            # After midnight, the trip may be scheduled as 24:xx the day before.
            day = _shift(start_date, -1)
            cands = self._running(k, k.origin + DAY, day)
        if len(cands) > 1 and k.path:
            cands = [c for c in cands if c[1] == k.path] or cands
        if len(cands) != 1:
            return None
        return Match(cands[0][0], day, cands[0][3])

    def _running(self, k: TripKey, origin: int, day: str) -> list:
        return [
            c for c in self._trips.get((k.route, k.direction, origin), ())
            if day in self._services.get(c[2], ())
        ]

    # The index is built from the GTFS zip at image build time, because
    # reading stop_times.txt takes seconds and the container starts cold.

    @staticmethod
    def index_gtfs_zip(path: str) -> dict:
        with zipfile.ZipFile(path) as z:
            def rows(name):
                if name not in z.namelist():
                    return []
                return csv.DictReader(io.TextIOWrapper(z.open(name), "utf-8-sig"))

            services = _service_dates(rows("calendar.txt"), rows("calendar_dates.txt"))
            trips = {r["trip_id"]: r["service_id"] for r in rows("trips.txt")}
            starts = _first_departures(rows("stop_times.txt"))
            routes = sorted(r["route_id"] for r in rows("routes.txt"))
            stops = {
                r["stop_id"]: [float(r["stop_lat"]), float(r["stop_lon"])]
                for r in rows("stops.txt")
            }
        return {
            "routes": routes,
            "stops": stops,
            "services": {s: sorted(d) for s, d in services.items()},
            "trips": [[t, s, starts.get(t, "")] for t, s in trips.items()],
        }

    @classmethod
    def from_index(cls, index: dict) -> "Timetable":
        return cls(index["trips"], index["services"], index["routes"], index["stops"])

    @classmethod
    def load(cls, path: str) -> "Timetable":
        with open(path) as f:
            return cls.from_index(json.load(f))


@dataclass
class FeedStats:
    trip_updates: int = 0
    matched: int = 0  # rewritten to a scheduled trip
    added: int = 0  # no scheduled trip: sent as an ADDED trip
    dropped: int = 0  # unreadable, or too little to add

    def __iadd__(self, o: "FeedStats") -> "FeedStats":
        self.trip_updates += o.trip_updates
        self.matched += o.matched
        self.added += o.added
        self.dropped += o.dropped
        return self


def rewrite_feed(feed: gtfs_realtime_pb2.FeedMessage, tt: Timetable) -> FeedStats:
    """Rewrite the feed's trip updates in place for MOTIS.

    Only trip descriptor fields change (trip id, start date and time, schedule
    relationship, and the route of added trips), so the MTA's NYCT extension
    fields pass through intact. Alerts pass through unchanged. Vehicle
    positions are dropped: MOTIS ignores them, logging a line for each.
    """
    stats = FeedStats()
    keep = []
    for e in feed.entity:
        if e.HasField("vehicle") and not (e.HasField("trip_update") or e.HasField("alert")):
            continue
        if e.HasField("trip_update"):
            stats.trip_updates += 1
            if not _rewrite_trip_update(e.trip_update, tt, stats):
                stats.dropped += 1
                continue
        keep.append(e)
    if len(keep) != len(feed.entity):
        del feed.entity[:]
        feed.entity.extend(keep)
    return stats


def _rewrite_trip_update(tu, tt: Timetable, stats: FeedStats) -> bool:
    trip = tu.trip
    if trip.schedule_relationship != TripDescriptor.SCHEDULED:
        return False  # the MTA sends none today; nothing to match them to
    m = tt.match(trip.trip_id, trip.start_date)
    if m is not None:
        trip.trip_id = m.trip_id
        trip.start_date = m.start_date
        # MOTIS skips a run whose start_time differs from the static first
        # departure, and the MTA's start_time often does by a minute or more.
        if m.start_time:
            trip.start_time = m.start_time
        else:
            trip.ClearField("start_time")
        stats.matched += 1
        return True
    if not _addable(tu, tt):
        return False
    _keep_plausible_stops(tu, tt)
    if len(tu.stop_time_update) < 2:
        return False
    # MOTIS needs a trip id that is not in the timetable (the realtime id is
    # not), a known route, and absolute times at known stops.
    trip.schedule_relationship = TripDescriptor.ADDED
    if trip.route_id not in tt.routes:
        trip.route_id = ROUTE_ALIASES.get(trip.route_id, trip.route_id)
    stats.added += 1
    return True


def _addable(tu, tt: Timetable) -> bool:
    k = parse_trip_id(tu.trip.trip_id)
    if k is None or not tu.trip.start_date:
        return False
    route = tu.trip.route_id
    if route not in tt.routes and ROUTE_ALIASES.get(route) not in tt.routes:
        return False
    timed = [
        s for s in tu.stop_time_update
        if s.stop_id and (s.departure.time or s.arrival.time)
    ]
    return len(timed) >= 2


def _keep_plausible_stops(tu, tt: Timetable) -> None:
    """Keep the stop updates MOTIS accepts for an added trip.

    MOTIS skips the whole trip if one stop is unknown or two stops imply
    more than 100 m/s, and the MTA sends both (stops missing from stops.txt,
    and placeholder times one second apart for stops the train skips).
    """
    keep, last = [], None
    for s in tu.stop_time_update:
        pos = tt.stops.get(s.stop_id)
        arr = s.arrival.time or s.departure.time
        dep = s.departure.time or s.arrival.time
        if pos is None or not arr:
            continue
        if last is not None:
            dt_s = arr - last[1]
            if dt_s <= 0 or _metres(last[0], pos) / dt_s > MAX_SPEED:
                continue
        keep.append(s)
        last = (pos, dep)
    if len(keep) != len(tu.stop_time_update):
        kept = [type(s)() for s in keep]
        for k, s in zip(kept, keep):
            k.CopyFrom(s)
        del tu.stop_time_update[:]
        tu.stop_time_update.extend(kept)


def _metres(a, b) -> float:
    lat1, lon1, lat2, lon2 = map(math.radians, (*a, *b))
    h = (math.sin((lat2 - lat1) / 2) ** 2
         + math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2)
    return 2 * 6371000 * math.asin(math.sqrt(h))


def _service_dates(calendar, calendar_dates) -> dict[str, set[str]]:
    dates: dict[str, set[str]] = defaultdict(set)
    weekdays = ["monday", "tuesday", "wednesday", "thursday", "friday",
                "saturday", "sunday"]
    for r in calendar:
        d, end = _date(r["start_date"]), _date(r["end_date"])
        while d <= end:
            if r[weekdays[d.weekday()]] == "1":
                dates[r["service_id"]].add(d.strftime("%Y%m%d"))
            d += dt.timedelta(days=1)
    for r in calendar_dates:
        if r["exception_type"] == "1":
            dates[r["service_id"]].add(r["date"])
        else:
            dates[r["service_id"]].discard(r["date"])
    return dates


def _first_departures(stop_times) -> dict[str, str]:
    """Departure time at the lowest stop_sequence of each trip."""
    first: dict[str, tuple[int, str]] = {}
    for r in stop_times:
        seq = int(r["stop_sequence"])
        cur = first.get(r["trip_id"])
        if cur is None or seq < cur[0]:
            first[r["trip_id"]] = (seq, r["departure_time"] or r["arrival_time"])
    return {t: v[1] for t, v in first.items()}


def _date(s: str) -> dt.date:
    return dt.date(int(s[:4]), int(s[4:6]), int(s[6:]))


def _shift(yyyymmdd: str, days: int) -> str:
    return (_date(yyyymmdd) + dt.timedelta(days=days)).strftime("%Y%m%d")

