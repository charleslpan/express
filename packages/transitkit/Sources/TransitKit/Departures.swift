import Foundation

/// One departure (or arrival) of a trip at a stop, from `stoptimes`.
public typealias Departure = Components.Schemas.StopTime

/// The answer to a ``DeparturesRequest``: the stop, its departures, and cursors to page through time.
public typealias DeparturesResponse = Operations.Stoptimes.Output.Ok.Body.JsonPayload

/// Departures or arrivals to fetch for a stop: which stop, from when, how many, and which page.
public struct DeparturesRequest: Sendable, Hashable {
    /// Whether to list the trips leaving the stop or the ones arriving at it.
    public enum Kind: Sendable, Hashable {
        case departures
        case arrivals
    }

    /// A stop or station id, such as `us-ny-MTA-NYCSubway_635`; a subway station's id returns its whole complex.
    public var stopId: String
    public var kind: Kind
    /// The time to list from; `nil` for now (the server's clock).
    public var time: Date?
    /// The minimum number of departures to return; `nil` for the server's default.
    public var count: Int?
    /// Also return every departure up to this many seconds after ``time``; with ``count`` too, whichever gives more.
    public var window: TimeInterval?
    /// The transit modes to list, such as `[.subway]`; `nil` lists every one.
    public var transitModes: [TransitMode]?
    /// A cursor from an earlier ``DeparturesResponse`` (``DeparturesResponse/laterPageCursor`` or
    /// ``DeparturesResponse/earlierPageCursor``) to fetch that page; keep the rest of the request unchanged.
    public var pageCursor: String?

    public init(
        stopId: String,
        kind: Kind = .departures,
        time: Date? = nil,
        count: Int? = nil,
        window: TimeInterval? = nil,
        transitModes: [TransitMode]? = nil,
        pageCursor: String? = nil
    ) {
        self.stopId = stopId
        self.kind = kind
        self.time = time
        self.count = count
        self.window = window
        self.transitModes = transitModes
        self.pageCursor = pageCursor
    }

    /// The same request, moved to another page.
    public func page(_ cursor: String) -> DeparturesRequest {
        var request = self
        request.pageCursor = cursor
        return request
    }

    var query: Operations.Stoptimes.Input.Query {
        var query = Operations.Stoptimes.Input.Query(stopId: stopId)
        query.time = time
        if kind == .arrivals {
            // MOTIS lists arrivals backwards from `time` unless told otherwise.
            query.arriveBy = true
            query.direction = .later
        }
        query.n = count
        query.window = window.map { Int($0.rounded()) }
        query.mode = transitModes
        query.pageCursor = pageCursor
        return query
    }
}

public extension DeparturesResponse {
    /// The cursor for the next page (later departures), to pass as ``DeparturesRequest/pageCursor``.
    var laterPageCursor: String? {
        nextPageCursor.isEmpty ? nil : nextPageCursor
    }

    /// The cursor for the previous page (earlier departures), to pass as ``DeparturesRequest/pageCursor``.
    var earlierPageCursor: String? {
        previousPageCursor.isEmpty ? nil : previousPageCursor
    }
}

extension Departure: Identifiable {
    /// A stable identity within a stop's list: trip, platform, and scheduled time.
    public var id: String {
        let time = scheduledTime.map { String(Int($0.timeIntervalSince1970)) } ?? ""
        return "\(tripId)|\(place.stopId ?? "")|\(time)"
    }
}

public extension Departure {
    /// When the trip leaves the stop (or, for an arrival, reaches it), with realtime data where there is some.
    var time: Date? {
        place.departure ?? place.arrival
    }

    /// When the timetable says the trip leaves (or reaches) the stop.
    var scheduledTime: Date? {
        place.scheduledDeparture ?? place.scheduledArrival
    }

    /// Whether realtime data stands behind ``time`` (MOTIS's `realTime`).
    var isRealtime: Bool {
        realTime
    }

    /// Whether realtime data cancels this stop: the stop is skipped, or the whole trip is cancelled.
    var isCancelled: Bool {
        cancelled || tripCancelled
    }

    /// Whole minutes late (positive) or early (negative), rounded to the nearest; `nil` without realtime data.
    var delayMinutes: Int? {
        place.departureDelayMinutes ?? place.arrivalDelayMinutes
    }

    /// Whole minutes from `now` until ``time``, for "leaves in N min": rounded down, and negative once gone.
    func minutesUntil(from now: Date) -> Int? {
        time.map { Int(($0.timeIntervalSince(now) / 60).rounded(.down)) }
    }

    /// The name riders know the line by: the route's short name ("L", "M14A-SBS"), else its long name, else the
    /// display name.
    var lineName: String? {
        [routeShortName, routeLongName, displayName].first { !$0.isEmpty }
    }

    /// The route's colour from the feed, if it gives one.
    var routeRGBColor: RGBColor? {
        routeColor.flatMap(RGBColor.init(hex:))
    }

    /// The colour the feed gives for text on ``routeRGBColor``, if any.
    var routeTextRGBColor: RGBColor? {
        routeTextColor.flatMap(RGBColor.init(hex:))
    }
}
