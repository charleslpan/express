"""Tests for alerts.py on the MTA's alert feeds as recorded on Nov 3, 2026
(about 21:30 UTC). Run from apps/api/motis/adapter:

    python3 -m unittest discover -s tests

Needs protobuf and gtfs-realtime-bindings (see the Dockerfile).
"""

import gzip
import json
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

from google.transit import gtfs_realtime_pb2  # noqa: E402

from alerts import AlertTypes, alerts_for_routes, fill_alerts, mta_alert_type  # noqa: E402

Alert = gtfs_realtime_pb2.Alert
FIXTURES = os.path.join(HERE, "fixtures", "alerts-20261103")
TYPES = AlertTypes.load()


def recorded(name):
    with gzip.open(os.path.join(FIXTURES, f"{name}.pb.gz")) as f:
        raw = f.read()
    feed = gtfs_realtime_pb2.FeedMessage()
    feed.ParseFromString(raw)
    return raw, feed


def alert_by_id(feed, alert_id):
    return next(e.alert for e in feed.entity if e.id == alert_id)


class AlertTypeTableTest(unittest.TestCase):
    def test_covers_every_type_in_the_recorded_feeds(self):
        for name in ("subway-alerts", "bus-alerts"):
            _, feed = recorded(name)
            kinds = {mta_alert_type(e.alert) for e in feed.entity}
            self.assertGreater(len(kinds), 5, name)
            unknown = sorted(k or "(none)" for k in kinds if TYPES.map(k) is None)
            self.assertEqual(unknown, [], f"{name}: add these to alert_types.json")

    def test_maps_types_and_the_planned_prefix(self):
        m = TYPES.map("Part Suspended")
        self.assertEqual((m.effect, m.cause, m.severity),
                         (Alert.NO_SERVICE, Alert.UNKNOWN_CAUSE, Alert.SEVERE))
        m = TYPES.map("Planned - Part Suspended")
        self.assertEqual((m.effect, m.cause, m.severity),
                         (Alert.NO_SERVICE, Alert.MAINTENANCE, Alert.SEVERE))
        self.assertEqual(TYPES.map("Delays").effect, Alert.SIGNIFICANT_DELAYS)
        self.assertEqual(TYPES.map("Boarding Change").effect, Alert.STOP_MOVED)
        self.assertEqual(TYPES.map("Planned - Detour").effect, Alert.DETOUR)

    def test_unknown_type_falls_back(self):
        self.assertIsNone(TYPES.map("Alien Invasion"))
        m = TYPES.resolve("Alien Invasion")
        self.assertEqual((m.effect, m.severity), (Alert.OTHER_EFFECT, Alert.INFO))
        self.assertEqual(TYPES.resolve("Planned - Alien Invasion").effect, Alert.OTHER_EFFECT)

    def test_table_names_only_valid_enum_values(self):
        with open(os.path.join(os.path.dirname(HERE), "alert_types.json")) as f:
            AlertTypes(json.load(f))  # raises on an unknown enum name


class FillAlertsTest(unittest.TestCase):
    def test_fills_the_standard_fields(self):
        _, feed = recorded("subway-alerts")
        self.assertTrue(all(not e.alert.HasField("effect") for e in feed.entity))
        stats = fill_alerts(feed, TYPES)
        self.assertEqual(stats.alerts, len(feed.entity))
        self.assertEqual(stats.unknown, {})
        self.assertNotIn(Alert.UNKNOWN_EFFECT, {e.alert.effect for e in feed.entity})

        delays = alert_by_id(feed, "lmm:alert:274734:26")  # 2 and 5, EMS at E 180 St
        self.assertEqual(mta_alert_type(delays), "Delays")
        self.assertEqual(delays.effect, Alert.SIGNIFICANT_DELAYS)
        self.assertEqual(delays.severity_level, Alert.WARNING)
        self.assertFalse(delays.HasField("cause"))

        planned = [e.alert for e in feed.entity
                   if mta_alert_type(e.alert).startswith("Planned - ")]
        self.assertTrue(planned)
        self.assertTrue(all(a.cause == Alert.MAINTENANCE for a in planned))

    def test_keeps_everything_else(self):
        for name in ("subway-alerts", "bus-alerts"):
            raw, feed = recorded(name)
            fill_alerts(feed, TYPES)
            # Decode the output afresh, clear the three fields, and it is the input.
            out = gtfs_realtime_pb2.FeedMessage()
            out.ParseFromString(feed.SerializeToString())
            for e in out.entity:
                self.assertIsNotNone(mta_alert_type(e.alert), "extension survives")
                for f in ("effect", "cause", "severity_level"):
                    e.alert.ClearField(f)
            self.assertEqual(out.SerializeToString(), raw, name)

    def test_respects_fields_the_feed_sets(self):
        _, feed = recorded("subway-alerts")
        a = alert_by_id(feed, "lmm:alert:274734:26")
        a.effect, a.cause, a.severity_level = Alert.DETOUR, Alert.WEATHER, Alert.SEVERE
        fill_alerts(feed, TYPES)
        self.assertEqual((a.effect, a.cause, a.severity_level),
                         (Alert.DETOUR, Alert.WEATHER, Alert.SEVERE))

    def test_counts_unknown_types(self):
        feed = gtfs_realtime_pb2.FeedMessage()
        feed.header.gtfs_realtime_version = "2.0"
        feed.entity.add(id="x").alert.header_text.translation.add(text="no type")
        stats = fill_alerts(feed, TYPES)
        self.assertEqual(stats.unknown, {"(none)": 1})
        self.assertEqual(feed.entity[0].alert.effect, Alert.OTHER_EFFECT)


class BusDatasetTest(unittest.TestCase):
    def test_keeps_alerts_naming_the_datasets_routes_whole(self):
        _, feed = recorded("bus-alerts")
        out = alerts_for_routes(feed, {"BM1", "B44+"})
        ids = {e.id for e in out.entity}
        self.assertIn("lmm:alert:274725:31", ids)  # BM1-BM4 detour, kept whole
        bm = alert_by_id(out, "lmm:alert:274725:31")
        self.assertEqual([ie.route_id for ie in bm.informed_entity], ["BM1", "BM2", "BM3", "BM4"])
        for e in out.entity:
            routes = {ie.route_id for ie in e.alert.informed_entity}
            self.assertTrue(routes & {"BM1", "B44+"}, e.id)
        self.assertEqual(out.header, feed.header)
        self.assertEqual(len(alerts_for_routes(feed, set()).entity), 0)


if __name__ == "__main__":
    unittest.main()
