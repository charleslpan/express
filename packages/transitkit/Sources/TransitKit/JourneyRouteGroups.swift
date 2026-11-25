import Foundation

// Journey options grouped by route: the same path taken by successive trips is one option with several departures,
// not several options. A route's identity ignores which trips ride it and when, and keeps everything that makes the
// way there different: the line, the direction, where the rider boards and alights, and where they change.

/// What makes one journey a different way there from another, with no regard to which trips ride it or when: for each
/// ride, its route, direction, and boarding and alighting stops, in order. A change at another station is another
/// route, since the alighting and boarding stops differ.
///
/// A journey whose rides lack an identifier that would tell it from another (a route or a stop id) has no pattern:
/// grouping it with another would be a guess, so it stands alone (``init(_:)`` returns `nil`).
public struct JourneyRoutePattern: Sendable, Hashable {
    /// One ride's place in the pattern.
    public struct Ride: Sendable, Hashable {
        public var routeId: String
        /// The direction the route runs, where the feed gives one: a ride with one and a ride without are not the
        /// same route.
        public var directionId: String?
        public var boardStopId: String
        public var alightStopId: String
    }

    /// The rides in order; empty for a journey on foot.
    public var rides: [Ride]

    /// The pattern of an itinerary's rides; `nil` where any ride lacks a route id or a stop id.
    public init?(_ itinerary: Itinerary) {
        var rides: [Ride] = []
        for leg in itinerary.legs where leg.tripId != nil {
            guard let routeId = leg.routeId, !routeId.isEmpty,
                  let boardStopId = leg.from.stopId, !boardStopId.isEmpty,
                  let alightStopId = leg.to.stopId, !alightStopId.isEmpty
            else { return nil }
            rides.append(Ride(
                routeId: routeId,
                directionId: leg.directionId.flatMap { $0.isEmpty ? nil : $0 },
                boardStopId: boardStopId,
                alightStopId: alightStopId
            ))
        }
        self.rides = rides
    }

    /// Whether the journey is a single ride: the only kind whose later departures can be found from its boarding
    /// stop alone, since nothing after it has to connect.
    public var isDirect: Bool {
        rides.count == 1
    }

    /// A stable identity for lists: stays the same as the trips and times underneath change.
    public var id: String {
        guard !rides.isEmpty else { return "walk" }
        return rides.map { "\($0.routeId)|\($0.directionId ?? "")|\($0.boardStopId)|\($0.alightStopId)" }
            .joined(separator: ">")
    }
}

/// One route and the journeys that take it: what a row of the options list stands for.
///
/// Every option in a group is a whole itinerary MOTIS planned (every ride and change checked against the
/// timetable), so each is a connection that works, not a first ride with a hope of a second.
public struct JourneyRouteGroup: Sendable, Hashable, Identifiable {
    /// The route's pattern id, or `option:<id>` for a journey with no pattern, which stands alone.
    public var id: String
    /// The route, when its identifiers allow it.
    public var pattern: JourneyRoutePattern?
    /// The group's options, best first as the list ranks them: ``primary`` is the first.
    public var options: [JourneyOption]

    /// The option the row shows: the best of the group, which is where the group sits in the list.
    public var primary: JourneyOption {
        options[0]
    }

    /// The other options, by when they leave (the first ride's departure, else the journey's start), soonest first.
    public var others: [JourneyOption] {
        options.dropFirst().sorted { $0.departureDate < $1.departureDate }
    }

    /// Every option by when it leaves, soonest first: the departures a rider can pick from.
    public var byDeparture: [JourneyOption] {
        options.sorted { $0.departureDate < $1.departureDate }
    }
}

extension JourneyOption {
    /// When the rider's first ride leaves, or, on foot, when the journey starts.
    var departureDate: Date {
        summary.firstRideDeparture ?? summary.departure
    }
}

public extension JourneyOptions {
    /// Collapses ranked options into one group per route, keeping the order: a group takes the place of its best
    /// option, so the list ranks exactly as it did and only repeats fold away. Options with no route pattern each
    /// stand alone. Only the first ``maxGroups`` groups are kept, after grouping, so a kept group has every one of its
    /// departures.
    static func groups(of options: [JourneyOption], limit: Int = maxGroups) -> [JourneyRouteGroup] {
        Array(allGroups(of: options).prefix(limit))
    }

    /// How many route groups the options list shows.
    static let maxGroups = 5

    private static func allGroups(of options: [JourneyOption]) -> [JourneyRouteGroup] {
        var groups: [JourneyRouteGroup] = []
        var indexByID: [String: Int] = [:]
        for option in options {
            let pattern = JourneyRoutePattern(option.itinerary)
            let id = pattern?.id ?? "option:\(option.id)"
            if let index = indexByID[id], pattern != nil {
                groups[index].options.append(option)
            } else {
                indexByID[id] = groups.count
                groups.append(JourneyRouteGroup(id: id, pattern: pattern, options: [option]))
            }
        }
        return groups
    }
}
