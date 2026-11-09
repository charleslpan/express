"""MTA service alerts made spec-conformant for MOTIS.

The MTA leaves the standard `effect`, `cause`, and `severity_level` empty and
says what an alert is in its own `mercury_alert` extension (field 1001 on
Alert, `alert_type` its field 3: "Delays", "Planned - Part Suspended", ...).
fill_alerts() fills the three standard fields from that type with the table in
alert_types.json, writes the type itself into `effect_detail`, and changes
nothing else: the extension and every other field survive decoding and
re-encoding as unknown fields.

MOTIS (v2.11.4, `include/motis/to_alert.h`) passes `effect_detail` through on
stoptimes and plan legs as `effectDetail`, but drops `severity_level` and the
extension, so `effect_detail` is how the app learns the type and, from the same
table, the severity line status shows.
"""

from __future__ import annotations

import json
import logging
import os
from dataclasses import dataclass, field

from google.transit import gtfs_realtime_pb2

Alert = gtfs_realtime_pb2.Alert
MERCURY_ALERT = 1001  # extension field on Alert
ALERT_TYPE = 3  # field of MercuryAlert
# Alert.effect_detail, a TranslatedString (translation 1: Translation, with text 1 and
# language 2). The pinned gtfs-realtime-bindings (2.0.0) predate it, so it is read and
# written as raw bytes, which survive as an unknown field.
EFFECT_DETAIL = 18

log = logging.getLogger("adapter")


@dataclass(frozen=True)
class Mapped:
    effect: int
    cause: int
    severity: int


@dataclass
class AlertStats:
    alerts: int = 0
    unknown: dict[str, int] = field(default_factory=dict)  # type -> count


class AlertTypes:
    """The alert-type table in alert_types.json."""

    def __init__(self, table: dict):
        self.prefix = table["plannedPrefix"]
        self.planned_cause = Alert.Cause.Value(table["plannedCause"])
        self.fallback = _entry(table["fallback"])
        self.types = {name: _entry(e) for name, e in table["types"].items()}

    @classmethod
    def load(cls, path: str | None = None) -> AlertTypes:
        path = path or os.path.join(os.path.dirname(os.path.abspath(__file__)), "alert_types.json")
        with open(path) as f:
            return cls(json.load(f))

    def map(self, alert_type: str | None) -> Mapped | None:
        """Effect, cause, and severity for an MTA type; None if the type is unknown."""
        if not alert_type:
            return None
        planned = alert_type.startswith(self.prefix)
        base = alert_type[len(self.prefix):] if planned else alert_type
        entry = self.types.get(alert_type) or self.types.get(base)
        if entry is None:
            return None
        effect, severity = entry
        cause = self.planned_cause if planned else Alert.Cause.UNKNOWN_CAUSE
        return Mapped(effect, cause, severity)

    def resolve(self, alert_type: str | None) -> Mapped:
        """Like map(), with the fallback for an unknown type."""
        return self.map(alert_type) or Mapped(self.fallback[0], Alert.Cause.UNKNOWN_CAUSE,
                                              self.fallback[1])


def _entry(e: dict) -> tuple[int, int]:
    return (Alert.Effect.Value(e["effect"]),
            Alert.SeverityLevel.Value(e["severity"]))


def mta_alert_type(alert: Alert) -> str | None:
    """The MTA's alert_type, read from the extension's raw bytes."""
    for num, wire, value in _fields(alert.SerializeToString()):
        if num == MERCURY_ALERT and wire == 2:
            for n, w, v in _fields(value):
                if n == ALERT_TYPE and w == 2:
                    return v.decode("utf-8", "replace")
    return None


def fill_alerts(feed: gtfs_realtime_pb2.FeedMessage, types: AlertTypes) -> AlertStats:
    """Fills effect, cause, and severity_level where the feed leaves them unset, and
    effect_detail with the MTA's type (in English) where the feed sets none."""
    stats = AlertStats()
    for entity in feed.entity:
        if not entity.HasField("alert"):
            continue
        alert = entity.alert
        stats.alerts += 1
        kind = mta_alert_type(alert)
        mapped = types.map(kind)
        if mapped is None:
            key = kind or "(none)"
            stats.unknown[key] = stats.unknown.get(key, 0) + 1
            mapped = types.resolve(kind)
        if not alert.HasField("effect") or alert.effect == Alert.Effect.UNKNOWN_EFFECT:
            alert.effect = mapped.effect
        if (mapped.cause != Alert.Cause.UNKNOWN_CAUSE
                and (not alert.HasField("cause") or alert.cause == Alert.Cause.UNKNOWN_CAUSE)):
            alert.cause = mapped.cause
        if (not alert.HasField("severity_level")
                or alert.severity_level == Alert.SeverityLevel.UNKNOWN_SEVERITY):
            alert.severity_level = mapped.severity
        if kind and effect_detail(alert) is None:
            alert.MergeFromString(_effect_detail_bytes(kind, "en"))
    return stats


def effect_detail(alert: Alert) -> list[tuple[str, str | None]] | None:
    """The alert's effect_detail as (text, language) pairs; None if it has none."""
    found = None
    for num, wire, value in _fields(alert.SerializeToString()):
        if num == EFFECT_DETAIL and wire == 2:
            found = found or []
            for n, w, translation in _fields(value):
                if n == 1 and w == 2:
                    parts = {k: v.decode("utf-8", "replace") for k, wt, v in _fields(translation) if wt == 2}
                    found.append((parts.get(1, ""), parts.get(2)))
    return found


def _effect_detail_bytes(text: str, language: str) -> bytes:
    """An Alert holding only effect_detail, encoded, to merge into another."""
    translation = _len_field(1, text.encode()) + _len_field(2, language.encode())
    return _len_field(EFFECT_DETAIL, _len_field(1, translation))


def _len_field(num: int, value: bytes) -> bytes:
    return _encode_varint(num << 3 | 2) + _encode_varint(len(value)) + value


def _encode_varint(n: int) -> bytes:
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            out.append(b | 0x80)
        else:
            out.append(b)
            return bytes(out)


def alerts_for_routes(feed: gtfs_realtime_pb2.FeedMessage,
                      routes: set[str]) -> gtfs_realtime_pb2.FeedMessage:
    """The alerts naming one of `routes`, or no route at all, each kept whole."""
    out = gtfs_realtime_pb2.FeedMessage()
    out.header.CopyFrom(feed.header)
    out.entity.extend(
        e for e in feed.entity
        if e.HasField("alert") and any(
            not ie.route_id or ie.route_id in routes for ie in e.alert.informed_entity)
    )
    return out


def _varint(b: bytes, i: int) -> tuple[int, int]:
    n = shift = 0
    while True:
        x = b[i]
        i += 1
        n |= (x & 0x7F) << shift
        if x < 0x80:
            return n, i
        shift += 7


def _fields(b: bytes):
    """Yields (field number, wire type, value) for each top-level field of a message."""
    i = 0
    while i < len(b):
        key, i = _varint(b, i)
        num, wire = key >> 3, key & 7
        if wire == 0:
            value, i = _varint(b, i)
        elif wire == 1:
            value, i = b[i:i + 8], i + 8
        elif wire == 2:
            n, i = _varint(b, i)
            value, i = b[i:i + n], i + n
        elif wire == 5:
            value, i = b[i:i + 4], i + 4
        else:  # groups: not used by GTFS-RT
            raise ValueError(f"unsupported wire type {wire}")
        yield num, wire, value
