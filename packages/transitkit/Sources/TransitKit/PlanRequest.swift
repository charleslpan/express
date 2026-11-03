import Foundation

/// A trip to plan: where from and to, when, by which modes, and which page of results.
public struct PlanRequest: Sendable, Hashable {
    /// One end of a trip: a coordinate, or a stop id such as `us-ny-MTA-NYCSubway_635`.
    public enum Waypoint: Sendable, Hashable {
        case coordinate(Coordinate)
        case stop(id: String)

        /// The `fromPlace`/`toPlace` value MOTIS expects: `latitude,longitude` or the stop id.
        var queryValue: String {
            switch self {
            case let .coordinate(coordinate): "\(coordinate.latitude),\(coordinate.longitude)"
            case let .stop(id): id
            }
        }
    }

    /// When the trip happens.
    public enum Time: Sendable, Hashable {
        /// Leave now (the server's clock).
        case now
        /// Leave at or after this time.
        case departAt(Date)
        /// Arrive at or before this time.
        case arriveBy(Date)
    }

    public var from: Waypoint
    public var to: Waypoint
    public var time: Time
    /// The transit modes allowed, such as `[.subway, .bus]`; `nil` allows every one.
    public var transitModes: [TransitMode]?
    /// The minimum number of itineraries to compute; `nil` for the server's default (5).
    public var numberOfItineraries: Int?
    /// A cursor from an earlier ``PlanResponse`` (``PlanResponse/laterPageCursor`` or
    /// ``PlanResponse/earlierPageCursor``) to fetch that page; keep the rest of the request unchanged.
    public var pageCursor: String?

    public init(
        from: Waypoint,
        to: Waypoint,
        time: Time = .now,
        transitModes: [TransitMode]? = nil,
        numberOfItineraries: Int? = nil,
        pageCursor: String? = nil
    ) {
        self.from = from
        self.to = to
        self.time = time
        self.transitModes = transitModes
        self.numberOfItineraries = numberOfItineraries
        self.pageCursor = pageCursor
    }

    /// The same request, moved to another page.
    public func page(_ cursor: String) -> PlanRequest {
        var request = self
        request.pageCursor = cursor
        return request
    }

    var query: Operations.Plan.Input.Query {
        var query = Operations.Plan.Input.Query(fromPlace: from.queryValue, toPlace: to.queryValue)
        switch time {
        case .now:
            break
        case let .departAt(date):
            query.time = date
            query.arriveBy = false
        case let .arriveBy(date):
            query.time = date
            query.arriveBy = true
        }
        query.transitModes = transitModes
        query.numItineraries = numberOfItineraries
        query.pageCursor = pageCursor
        return query
    }
}
