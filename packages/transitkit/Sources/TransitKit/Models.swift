/// A journey from one place to another: walking, transit, and transfer legs, as MOTIS plans it.
public typealias Itinerary = Components.Schemas.Itinerary

/// One part of an ``Itinerary``: a walk, or a ride on one transit trip.
public typealias Leg = Components.Schemas.Leg

/// A stop, a station, or a coordinate, with the times an ``Itinerary`` passes it.
public typealias Place = Components.Schemas.Place

/// A way of travelling: a transit mode (`.subway`, `.bus`, `.regionalRail`, …) or a street mode (`.walk`, `.bike`, …).
public typealias TransitMode = Components.Schemas.Mode

/// One turn-by-turn step of a walk: a direction, a street, and a distance.
public typealias StepInstruction = Components.Schemas.StepInstruction

/// A Google-encoded polyline, with the precision MOTIS encoded it at.
public typealias EncodedPolyline = Components.Schemas.EncodedPolyline

/// Why a time on a ``Place`` is what it is: scheduled only, or observed, propagated, or predicted from realtime data.
public typealias TimestampReason = Components.Schemas.TimestampReason

/// The answer to a ``PlanRequest``: itineraries, direct (street-only) options, and cursors to page through time.
public typealias PlanResponse = Operations.Plan.Output.Ok.Body.JsonPayload

extension Itinerary: Identifiable {}

extension Leg: Identifiable {
    /// A stable identity within an itinerary: mode, trip, origin, and scheduled departure.
    public var id: String {
        let origin = from.stopId ?? "\(from.lat),\(from.lon)"
        return "\(mode.rawValue)|\(tripId ?? "")|\(origin)|\(Int(scheduledStartTime.timeIntervalSince1970))"
    }
}

extension Place: Identifiable {
    /// The stop id where the place is a stop, else its coordinate.
    public var id: String {
        stopId ?? "\(lat),\(lon)"
    }
}

public extension PlanResponse {
    /// The cursor for the next page (later departures), to pass as ``PlanRequest/pageCursor``.
    var laterPageCursor: String? {
        nextPageCursor.isEmpty ? nil : nextPageCursor
    }

    /// The cursor for the previous page (earlier departures), to pass as ``PlanRequest/pageCursor``.
    var earlierPageCursor: String? {
        previousPageCursor.isEmpty ? nil : previousPageCursor
    }
}
