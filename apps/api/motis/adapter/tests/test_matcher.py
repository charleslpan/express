"""Tests for matcher.py. Run from apps/api/motis/adapter:

    python3 -m unittest discover -s tests

Needs protobuf and gtfs-realtime-bindings (see the Dockerfile).
"""

import glob
import gzip
import json
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

from google.transit import gtfs_realtime_pb2  # noqa: E402

from matcher import Match, Timetable, TripDescriptor, rewrite_feed  # noqa: E402

FIXTURES = os.path.join(HERE, "fixtures", "20261103-midday")
DAY = "20261103"
STOPS = {  # about 1 km apart, north to south
    "S1N": (40.70, -74.0), "S2N": (40.709, -74.0), "S3N": (40.718, -74.0),
}


def timetable(*trip_ids, start="12:00:00", dates=(DAY,)):
    return Timetable(
        [(t, "svc", start) for t in trip_ids],
        {"svc": list(dates)},
        routes=["1", "6", "6X", "A", "L", "N", "SI", "W"],
        stops=STOPS,
    )


def trip_update(trip_id, route, start_date=DAY, stops=(), start_time=""):
    feed = gtfs_realtime_pb2.FeedMessage()
    feed.header.gtfs_realtime_version = "1.0"
    tu = feed.entity.add(id="1").trip_update
    tu.trip.trip_id = trip_id
    tu.trip.route_id = route
    tu.trip.start_date = start_date
    if start_time:
        tu.trip.start_time = start_time
    for stop_id, t in stops:
        u = tu.stop_time_update.add(stop_id=stop_id)
        u.arrival.time = t
        u.departure.time = t
    return feed


class MatchRules(unittest.TestCase):
    def test_l_short_id_matches_static_with_path(self):
        tt = timetable("BFA26GEN-L028-Weekday-00_113500_L..S01R")
        self.assertEqual(tt.match("113500_L..S", DAY).trip_id,
                         "BFA26GEN-L028-Weekday-00_113500_L..S01R")

    def test_path_breaks_ties(self):
        tt = timetable("X_100350_A..S87R", "X_100350_A..S58R")
        self.assertEqual(tt.match("100350_A..S87R", DAY).trip_id, "X_100350_A..S87R")
        self.assertIsNone(tt.match("100350_A..S", DAY), "ambiguous without a path")

    def test_sir_one_dot_matches_two_dots_and_back(self):
        tt = timetable("L0S1-SI-1017-S03_113600_SI..N03R")
        self.assertIsNotNone(tt.match("113600_SI.N03R", DAY))
        tt = timetable("L0S1-SI-1017-S03_113600_SI.N03R")
        self.assertIsNotNone(tt.match("113600_SI..N03R", DAY))

    def test_sir_realtime_route_ss_is_si(self):
        tt = timetable("L0S1-SI-1017-S03_113600_SI.N03R")
        self.assertEqual(tt.match("113600_SS.N03R", DAY).trip_id,
                         "L0S1-SI-1017-S03_113600_SI.N03R")

    def test_express_tokens_normalised(self):
        tt = timetable("A_050000_6..N01R", "A_050000_7..S35R", "B_050000_F..N69R")
        self.assertIsNotNone(tt.match("050000_6X..N01R", DAY))
        self.assertIsNotNone(tt.match("050000_7X..S35R", DAY))
        self.assertIsNotNone(tt.match("050000_FX..N69R", DAY))

    def test_w_trains_keyed_by_id_token_not_route(self):
        tt = timetable("B_073600_N..N33R")
        feed = trip_update("073600_N..N33R", "W")
        s = rewrite_feed(feed, tt)
        self.assertEqual(s.matched, 1)
        self.assertEqual(feed.entity[0].trip_update.trip.trip_id, "B_073600_N..N33R")

    def test_no_match_by_nearest_time(self):
        tt = timetable("X_071350_B..N65R", "X_071200_B..N65R")
        self.assertIsNone(tt.match("071500_B..N65R", DAY))

    def test_service_must_run_on_start_date(self):
        tt = timetable("X_071350_B..N65R", dates=("20261104",))
        self.assertIsNone(tt.match("071350_B..N65R", DAY))

    def test_after_midnight_scheduled_as_24h_the_day_before(self):
        tt = timetable("X_145000_1..S03R", start="24:10:00", dates=("20261102",))
        self.assertEqual(tt.match("001000_1..S03R", DAY),
                         Match("X_145000_1..S03R", "20261102", "24:10:00"))

    def test_unreadable_ids(self):
        tt = timetable("X_071350_B..N65R")
        self.assertIsNone(tt.match("garbage", DAY))
        self.assertIsNone(tt.match("071350_B..N65R", ""))


class Rewrite(unittest.TestCase):
    def test_matched_trip_takes_static_id_and_start(self):
        tt = timetable("X_072150_A..N55R", start="12:02:00")
        feed = trip_update("072150_A..N55R", "A", start_time="12:01:30")
        rewrite_feed(feed, tt)
        trip = feed.entity[0].trip_update.trip
        self.assertEqual((trip.trip_id, trip.start_date, trip.start_time),
                         ("X_072150_A..N55R", DAY, "12:02:00"))
        self.assertEqual(trip.schedule_relationship, TripDescriptor.SCHEDULED)

    def test_unmatched_train_is_added_with_its_own_times(self):
        tt = timetable("X_071350_B..N65R")
        feed = trip_update("071500_A..N65R", "A",
                           stops=[("S1N", 1000), ("S2N", 1100), ("S3N", 1200)])
        s = rewrite_feed(feed, tt)
        self.assertEqual((s.matched, s.added, s.dropped), (0, 1, 0))
        trip = feed.entity[0].trip_update.trip
        self.assertEqual(trip.trip_id, "071500_A..N65R")
        self.assertEqual(trip.schedule_relationship, TripDescriptor.ADDED)

    def test_added_sir_route_ss_becomes_si(self):
        feed = trip_update("113600_SS.N03R", "SS",
                           stops=[("S1N", 1000), ("S2N", 1100)])
        rewrite_feed(feed, timetable())
        self.assertEqual(feed.entity[0].trip_update.trip.route_id, "SI")

    def test_added_trip_drops_unknown_and_impossible_stops(self):
        feed = trip_update("071500_A..N65R", "A", stops=[
            ("S1N", 1000), ("X22N", 1050), ("S2N", 1001), ("S3N", 1200)])
        s = rewrite_feed(feed, timetable())
        self.assertEqual(s.added, 1)
        stops = [u.stop_id for u in feed.entity[0].trip_update.stop_time_update]
        self.assertEqual(stops, ["S1N", "S3N"])

    def test_added_trip_needs_two_stops_and_a_known_route(self):
        s = rewrite_feed(trip_update("071500_A..N65R", "A", stops=[("S1N", 1000)]),
                         timetable())
        self.assertEqual(s.dropped, 1)
        s = rewrite_feed(trip_update("071500_Q..N65R", "Q",
                                     stops=[("S1N", 1000), ("S2N", 1100)]), timetable())
        self.assertEqual(s.dropped, 1)


class RecordedFeeds(unittest.TestCase):
    """The 8 live feeds recorded on Nov 3, 2026 at 1:45 PM in New York."""

    @classmethod
    def setUpClass(cls):
        with open(os.path.join(FIXTURES, "timetable.json")) as f:
            cls.tt = Timetable.from_index(json.load(f))
        cls.raw = {}
        for path in sorted(glob.glob(os.path.join(FIXTURES, "*.pb.gz"))):
            with gzip.open(path) as f:
                cls.raw[os.path.basename(path)[:-6]] = f.read()

    def feeds(self):
        for name, raw in self.raw.items():
            before, after = gtfs_realtime_pb2.FeedMessage(), gtfs_realtime_pb2.FeedMessage()
            before.ParseFromString(raw)
            after.ParseFromString(raw)
            yield name, before, after, rewrite_feed(after, self.tt)

    def test_match_rates(self):
        self.assertEqual(len(self.raw), 8)
        got = {name: (s.trip_updates, s.matched, s.added, s.dropped)
               for name, _, _, s in self.feeds()}
        self.assertEqual(got, {
            "gtfs": (243, 241, 2, 0),
            "gtfs-ace": (121, 119, 2, 0),
            "gtfs-bdfm": (160, 138, 22, 0),
            "gtfs-g": (24, 24, 0, 0),
            "gtfs-jz": (24, 24, 0, 0),
            "gtfs-l": (26, 26, 0, 0),
            "gtfs-nqrw": (128, 126, 2, 0),
            "gtfs-si": (8, 8, 0, 0),
        })

    def test_each_scheduled_trip_matched_at_most_once(self):
        for name, _, after, _ in self.feeds():
            ids = [e.trip_update.trip.trip_id for e in after.entity
                   if e.HasField("trip_update")
                   and e.trip_update.trip.schedule_relationship == TripDescriptor.SCHEDULED]
            self.assertEqual(len(ids), len(set(ids)), name)

    def test_nyct_extensions_and_alerts_kept(self):
        changed = ("trip_id", "start_time", "start_date", "schedule_relationship",
                   "route_id")
        for name, before, after, _ in self.feeds():
            # The header carries the NYCT feed extension.
            self.assertEqual(before.header.SerializeToString(),
                             after.header.SerializeToString(), name)
            old = {e.id: e for e in before.entity}
            self.assertEqual(
                sum(1 for e in before.entity if e.HasField("alert")),
                sum(1 for e in after.entity if e.HasField("alert")), name)
            for e in after.entity:
                o = old[e.id]
                self.assertFalse(e.HasField("vehicle"), "vehicle positions dropped")
                if not e.HasField("trip_update"):
                    self.assertEqual(o.SerializeToString(), e.SerializeToString())
                    continue
                a, b = gtfs_realtime_pb2.TripDescriptor(), gtfs_realtime_pb2.TripDescriptor()
                a.CopyFrom(o.trip_update.trip)
                b.CopyFrom(e.trip_update.trip)
                for f in changed:
                    a.ClearField(f)
                    b.ClearField(f)
                # What is left is the NYCT trip descriptor extension.
                self.assertTrue(a.SerializeToString(), name)
                self.assertEqual(a.SerializeToString(), b.SerializeToString(), name)

    def test_l_and_sir_quirks_present_and_matched(self):
        for name, before, after, s in self.feeds():
            if name == "gtfs-l":
                self.assertTrue(all(e.trip_update.trip.trip_id.endswith(("..N", "..S"))
                                    for e in before.entity if e.HasField("trip_update")))
                self.assertEqual(s.matched, s.trip_updates)
            if name == "gtfs-si":
                self.assertTrue(any("_SI.N" in e.trip_update.trip.trip_id
                                    or "_SI.S" in e.trip_update.trip.trip_id
                                    for e in before.entity if e.HasField("trip_update")))
                self.assertEqual(s.matched, s.trip_updates)


if __name__ == "__main__":
    unittest.main()
