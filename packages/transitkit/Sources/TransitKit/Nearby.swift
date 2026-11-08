import Foundation

// The logic behind a "nearby departures" board: which stops are near, their departures grouped by line and direction,
// how each departure stands against the timetable, and when the board may no longer be real time.

/// How a departure stands against the timetable, for the words beside its countdown.
public enum DepartureStatus: Sendable, Hashable {
    /// From the timetable alone: no realtime data stands behind it.
    case scheduled
    /// From a live feed, within a minute of the timetable.
    case onTime
    /// From a live feed, `minutes` late (at least ``DepartureStatus/delayThreshold``).
    case late(minutes: Int)
    /// From a live feed, `minutes` early (at least ``DepartureStatus/delayThreshold``).
    case early(minutes: Int)
    /// Cancelled by realtime data: the stop is skipped, or the trip won't run.
    case cancelled
    /// From a live feed that has gone stale, so it may not be real time (see ``NearbyBoard/mayNotBeRealTime(at:)``).
    case uncertain

    /// The smallest difference from the timetable, in whole minutes, worth calling late or early; smaller ones are
    /// noise in the MTA's predictions and read as on time.
    public static let delayThreshold = 2

    /// The words for the status: "On time", "3 min late", "2 min early", "Scheduled", "Cancelled", or
    /// "May not be real time". English until the app localizes.
    public var text: String {
        switch self {
        case .scheduled: "Scheduled"
        case .onTime: "On time"
        case let .late(minutes): "\(minutes) min late"
        case let .early(minutes): "\(minutes) min early"
        case .cancelled: "Cancelled"
        case .uncertain: "May not be real time"
        }
    }
}

public extension Departure {
    /// How the departure stands against the timetable; ``DepartureStatus/uncertain`` for a live time when the
    /// realtime data is stale.
    func status(realtimeIsStale: Bool = false) -> DepartureStatus {
        if isCancelled {
            return .cancelled
        }
        guard isRealtime else { return .scheduled }
        if realtimeIsStale {
            return .uncertain
        }
        let delay = delayMinutes ?? 0
        if delay >= DepartureStatus.delayThreshold {
            return .late(minutes: delay)
        }
        if delay <= -DepartureStatus.delayThreshold {
            return .early(minutes: -delay)
        }
        return .onTime
    }
}

/// Formats a departure's countdown.
public enum CountdownFormat {
    /// Whole minutes until a departure as riders read it: "Now" under a minute, else "4 min".
    public static func string(minutes: Int) -> String {
        minutes <= 0 ? "Now" : "\(minutes) min"
    }
}

/// One line's next departures in one direction at a stop, such as the uptown 6 at Union Square: what a departure
/// row shows.
public struct LineDepartures: Sendable, Hashable, Identifiable {
    /// The route and direction, such as `us-ny-MTA-NYCSubway_6|0`.
    public var id: String
    public var routeId: String
    public var directionId: String
    /// Where the next departure is headed, such as "Pelham Bay Park".
    public var headsign: String
    public var mode: TransitMode
    public var bullet: LineBullet
    /// The departures still to leave, soonest first; cancelled ones stay, so riders see them.
    public var departures: [Departure]

    /// The next departure that will run, which the line's place in a list goes by.
    public var next: Departure? {
        departures.first { !$0.isCancelled }
    }

    /// The headsign as riders read it: without the "SELECT BUS " the MTA starts Select Bus headsigns with, since the
    /// line's badge already says SBS.
    public var displayHeadsign: String {
        let prefix = "SELECT BUS "
        return headsign.hasPrefix(prefix) ? String(headsign.dropFirst(prefix.count)) : headsign
    }
}

public extension Sequence<Departure> {
    /// The departures still to leave at `now`, grouped by line and direction, with the soonest-leaving group first.
    ///
    /// A departure counts as gone once its minute has passed (``Departure/minutesUntil(from:)`` is negative). Each
    /// group keeps its first `limit` departures; a group whose departures are all cancelled sorts last. Groups that
    /// leave at the same time sort by line name, then direction. Copies of a departure (the same trip, platform,
    /// and time, as two requests for neighbouring stops may both return) count once.
    func groupedByLineAndDirection(at now: Date, limit: Int = 3) -> [LineDepartures] {
        var seen: Set<String> = []
        var groups: [String: LineDepartures] = [:]
        var order: [String] = []
        let upcoming = filter { ($0.minutesUntil(from: now) ?? -1) >= 0 }
            .sorted { ($0.time ?? .distantPast) < ($1.time ?? .distantPast) }
        for departure in upcoming where seen.insert(departure.id).inserted {
            guard let bullet = departure.lineBullet else { continue }
            let key = "\(departure.routeId)|\(departure.directionId)"
            if groups[key] == nil {
                order.append(key)
                groups[key] = LineDepartures(
                    id: key,
                    routeId: departure.routeId,
                    directionId: departure.directionId,
                    headsign: departure.headsign,
                    mode: departure.mode,
                    bullet: bullet,
                    departures: []
                )
            }
            if let count = groups[key]?.departures.count, count < limit {
                groups[key]?.departures.append(departure)
            }
        }
        return order.compactMap { groups[$0] }.sorted { lhs, rhs in
            let left = lhs.next?.time ?? .distantFuture
            let right = rhs.next?.time ?? .distantFuture
            if left != right {
                return left < right
            }
            if lhs.bullet.text != rhs.bullet.text {
                return lhs.bullet.text.localizedStandardCompare(rhs.bullet.text) == .orderedAscending
            }
            return lhs.directionId < rhs.directionId
        }
    }
}

/// A stop near the rider: a subway station (its whole complex) or a bus stop (both sides of the street).
public struct NearbyStop: Sendable, Hashable, Identifiable {
    /// The id to ask for the stop's departures by (``DeparturesRequest/stopId``).
    public var id: String
    public var name: String
    /// The modes that serve the stop.
    public var modes: [TransitMode]
    public var coordinate: Coordinate
    /// How far the stop is from the rider, in metres, as the crow flies.
    public var distance: Double

    public init(id: String, name: String, modes: [TransitMode], coordinate: Coordinate, distance: Double) {
        self.id = id
        self.name = name
        self.modes = modes
        self.coordinate = coordinate
        self.distance = distance
    }

    /// Whether a subway train calls here.
    public var isSubway: Bool {
        modes.contains(.subway)
    }

    /// The name as riders read it: the MTA's all-capitals bus stop names in title case ("E 14 St/Irving Pl"),
    /// other names as they are ("14 St-Union Sq").
    public var displayName: String {
        name.contains(where: \.isLowercase) ? name : name.capitalized(with: Locale(identifier: "en_US_POSIX"))
    }

    /// About how many minutes the walk takes, at least one: the distance, a quarter longer for the street grid, at
    /// 80 metres a minute.
    public var walkingMinutes: Int {
        max(1, Int((distance * 1.25 / 80).rounded(.up)))
    }

    /// How far a bus stop may be from another of the same name and still count as the same stop across the
    /// street, in metres.
    public static let streetCrossing: Double = 100
}

public extension Sequence<Stop> {
    /// The stations nearest `location`, nearest first, as stops to list departures for: at most `limit`, with the
    /// nearest subway station first wherever there is one, since that's the stop riders usually want.
    ///
    /// The stops are gathered into stations (``Swift/Sequence/groupedIntoStations(complexRadius:)``), and bus stops
    /// that share a name within ``NearbyStop/streetCrossing`` of each other, such as the poles on either side of a
    /// street, count as one: MOTIS lists both sides' departures for either.
    func nearbyStops(around location: Coordinate, limit: Int) -> [NearbyStop] {
        var stops: [NearbyStop] = []
        for station in groupedIntoStations() {
            let candidate = NearbyStop(
                id: station.id,
                name: station.name,
                modes: station.modes,
                coordinate: station.coordinate,
                distance: station.coordinate.distance(to: location)
            )
            let twin = stops.firstIndex { stop in
                !stop.isSubway && !candidate.isSubway && stop.name == candidate.name
                    && stop.coordinate.distance(to: candidate.coordinate) <= NearbyStop.streetCrossing
            }
            if let twin {
                // Keep the nearer side.
                if candidate.distance < stops[twin].distance {
                    stops[twin] = candidate
                }
            } else {
                stops.append(candidate)
            }
        }
        stops.sort { $0.distance < $1.distance }
        if let subway = stops.firstIndex(where: \.isSubway), subway > 0 {
            stops.insert(stops.remove(at: subway), at: 0)
        }
        return Array(stops.prefix(limit))
    }
}

/// A stop near the rider with its next departures by line and direction.
public struct NearbyDepartures: Sendable, Hashable, Identifiable {
    public var stop: NearbyStop
    /// Soonest first, from ``Swift/Sequence/groupedByLineAndDirection(at:limit:)``.
    public var lines: [LineDepartures]

    public init(stop: NearbyStop, lines: [LineDepartures]) {
        self.stop = stop
        self.lines = lines
    }

    public var id: String {
        stop.id
    }
}

/// The stops near the rider and their departures, as fetched at one moment.
public struct NearbyBoard: Sendable, Hashable {
    /// The stops with departures still to leave, in the order ``Swift/Sequence/nearbyStops(around:limit:)`` gave;
    /// stops with none are left out.
    public var stops: [NearbyDepartures]
    /// When the departures were fetched.
    public var fetchedAt: Date
    /// How old the server's realtime data was when they were fetched.
    public var dataAge: RealtimeDataAge

    /// Builds the board from each stop's departures, keeping the stops that have any left at `fetchedAt`.
    ///
    /// - Parameter linesPerStop: How many lines (in one direction each) to keep per stop.
    public init(
        stops: [NearbyStop],
        departures: [String: [Departure]],
        fetchedAt: Date,
        dataAge: RealtimeDataAge,
        linesPerStop: Int = 12
    ) {
        self.stops = stops.compactMap { stop in
            let lines = (departures[stop.id] ?? []).groupedByLineAndDirection(at: fetchedAt)
            return lines.isEmpty ? nil : NearbyDepartures(stop: stop, lines: Array(lines.prefix(linesPerStop)))
        }
        self.fetchedAt = fetchedAt
        self.dataAge = dataAge
    }

    /// Whether there's nothing to show: no stop has a departure left.
    public var isEmpty: Bool {
        stops.isEmpty
    }

    /// Whether screens must say times may not be real time, as the MTA's terms require: the board was fetched more
    /// than ``RealtimeDataAge/realTimeLimit`` ago (such as when refreshing has failed since), or the server's
    /// realtime data was older than that, or of unknown age, when it was.
    public func mayNotBeRealTime(at now: Date) -> Bool {
        now.timeIntervalSince(fetchedAt) > RealtimeDataAge.realTimeLimit || dataAge.mayNotBeRealTime(at: now)
    }
}
