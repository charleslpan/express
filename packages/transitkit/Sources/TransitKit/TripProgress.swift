import Foundation

// The logic behind following one trip: the stops it calls at with their live times, which it has passed, and where
// the vehicle is estimated to be between them.

/// One stop a trip calls at, with its times there (realtime where the feed predicts them).
public struct TripStop: Sendable, Hashable, Identifiable {
    /// The stop's place in the trip and its id, so a trip that calls at a stop twice lists it twice.
    public var id: String
    public var place: Place

    init(index: Int, place: Place) {
        id = "\(index)|\(place.id)"
        self.place = place
    }

    /// The stop's name, such as "14 St-Union Sq".
    public var name: String {
        place.name
    }

    /// When the vehicle gets to the stop: its arrival, or for the first stop its departure.
    public var time: Date? {
        place.arrival ?? place.departure
    }

    /// When the timetable says it gets there.
    public var scheduledTime: Date? {
        place.scheduledArrival ?? place.scheduledDeparture
    }

    /// When the vehicle leaves the stop: its departure, or for the last stop its arrival.
    public var leaveTime: Date? {
        place.departure ?? place.arrival
    }

    /// Whether realtime data stands behind the stop's times.
    public var isRealtime: Bool {
        place.isRealtime
    }

    /// Whether realtime data skips the stop.
    public var isCancelled: Bool {
        place.cancelled == true
    }

    /// Whole minutes late (positive) or early (negative) at the stop, arrival first; `nil` without realtime data.
    public var delayMinutes: Int? {
        place.arrivalDelayMinutes ?? place.departureDelayMinutes
    }

    /// How the stop's time stands against the timetable; ``DepartureStatus/uncertain`` for a live time when the
    /// realtime data is stale.
    public func status(realtimeIsStale: Bool = false) -> DepartureStatus {
        DepartureStatus(
            delayMinutes: delayMinutes,
            isRealtime: isRealtime,
            isCancelled: isCancelled,
            realtimeIsStale: realtimeIsStale
        )
    }
}

/// Where a vehicle is estimated to be on its trip: standing at a stop, or on the way between two.
///
/// The subway has no GPS, so this comes from the trip's times at its stops, spread evenly along the track between
/// them, as ``TrainRun/position(at:)`` places trains on the map.
public struct TripVehicle: Sendable, Hashable {
    public var coordinate: Coordinate
    /// The direction of travel, in degrees clockwise from north.
    public var bearing: Double
    /// The index in ``TripProgress/stops`` of the stop the vehicle last left, or stands at.
    public var fromIndex: Int
    /// The index of the stop it runs to next; the same as ``fromIndex`` while it stands at a stop.
    public var toIndex: Int

    /// Whether the vehicle stands at ``fromIndex``.
    public var isAtStop: Bool {
        fromIndex == toIndex
    }
}

/// How far a trip has got at a moment: its stops, which it has passed, and where its vehicle is.
public struct TripProgress: Sendable, Hashable {
    /// Where the trip stands as a whole.
    public enum Phase: Sendable, Hashable {
        /// The vehicle hasn't left its first stop yet.
        case notStarted
        /// The vehicle is on its way, or standing at a stop along it.
        case running
        /// The vehicle has reached its last stop.
        case ended
    }

    /// The stops the trip calls at, first to last.
    public var stops: [TripStop]
    /// How many of ``stops``, from the first, the vehicle has passed.
    public var passedCount: Int
    /// Where the vehicle is; `nil` before it sets off and once it has arrived.
    public var vehicle: TripVehicle?
    public var phase: Phase
    /// The trip's track, decoded from its legs' geometry; empty where the server sent none.
    public var path: [Coordinate]

    /// Works out how far `trip` (an itinerary from ``TransitClient/trip(id:)``) has got at `now`.
    ///
    /// A stop counts as passed once the vehicle has left it (its ``TripStop/leaveTime`` is at or before `now`), and so
    /// does every stop before the latest one passed, whatever their own times say, so the list greys out from the top
    /// without gaps. A vehicle that has reached a stop and not yet left it stands there, and the stop isn't passed.
    public init(trip: Itinerary, at now: Date) {
        let stops = trip.tripStops.enumerated().map { TripStop(index: $0.offset, place: $0.element) }
        let passed = stops.lastIndex { $0.leaveTime.map { $0 <= now } ?? false }.map { $0 + 1 } ?? 0
        self.stops = stops
        passedCount = passed
        path = trip.coordinates

        if passed >= stops.count {
            phase = .ended
            vehicle = nil
        } else if passed == 0 {
            // Waiting at, or not yet at, the first stop.
            phase = .notStarted
            vehicle = nil
        } else {
            phase = .running
            vehicle = Self.vehicle(stops: stops, passed: passed, path: path, at: now)
        }
    }

    /// Whether the vehicle has passed the stop at `index`.
    public func isPassed(_ index: Int) -> Bool {
        index < passedCount
    }

    /// The stop the vehicle stands at or runs to next; `nil` once the trip has ended.
    public var nextStop: TripStop? {
        passedCount < stops.count ? stops[passedCount] : nil
    }

    /// The vehicle's estimated position while it's running: standing at the next stop where it has got there and
    /// not left, else between the last stop passed and the next, as far along the track as the time gone says.
    private static func vehicle(stops: [TripStop], passed: Int, path: [Coordinate], at now: Date) -> TripVehicle? {
        let next = stops[passed]
        let along = TrackDistances(path: path, stops: stops.map(\.place.coordinate))
        if let arrival = next.time, arrival <= now {
            let bearing = passed + 1 < stops.count
                ? next.place.coordinate.bearing(to: stops[passed + 1].place.coordinate)
                : stops[passed - 1].place.coordinate.bearing(to: next.place.coordinate)
            return TripVehicle(coordinate: next.place.coordinate, bearing: bearing, fromIndex: passed, toIndex: passed)
        }
        guard passed > 0 else { return nil }
        let previous = stops[passed - 1]
        guard let left = previous.leaveTime, let arrival = next.time else { return nil }
        let duration = arrival.timeIntervalSince(left)
        let fraction = duration > 0 ? min(max(now.timeIntervalSince(left) / duration, 0), 1) : 1
        let fallbackBearing = previous.place.coordinate.bearing(to: next.place.coordinate)
        guard let point = along.point(between: passed - 1, and: passed, fraction: fraction) else {
            let from = previous.place.coordinate
            let to = next.place.coordinate
            let coordinate = Coordinate(
                latitude: from.latitude + (to.latitude - from.latitude) * fraction,
                longitude: from.longitude + (to.longitude - from.longitude) * fraction
            )
            return TripVehicle(coordinate: coordinate, bearing: fallbackBearing, fromIndex: passed - 1, toIndex: passed)
        }
        return TripVehicle(
            coordinate: point.coordinate,
            bearing: point.bearing ?? fallbackBearing,
            fromIndex: passed - 1,
            toIndex: passed
        )
    }
}

/// A trip's track measured from its start, with each stop placed at the track's nearest point to it, so a vehicle
/// between two stops can be placed on the track rather than on a straight line.
private struct TrackDistances {
    let path: PolylinePath
    /// How far along ``path`` each stop lies, in metres; never less than the stop before.
    let stops: [Double]

    init(path coordinates: [Coordinate], stops: [Coordinate]) {
        path = PolylinePath(coordinates)
        var cumulative: [Double] = []
        for (index, coordinate) in coordinates.enumerated() {
            cumulative.append(index == 0 ? 0 : cumulative[index - 1] + coordinates[index - 1].distance(to: coordinate))
        }
        // Each stop at the nearest vertex at or after the previous stop's, so stops stay in order on a looping track.
        var placed: [Double] = []
        var start = 0
        for stop in stops {
            guard !coordinates.isEmpty else { break }
            var best = start
            var bestDistance = Double.infinity
            for index in start ..< coordinates.count {
                let distance = coordinates[index].distance(to: stop)
                if distance < bestDistance {
                    best = index
                    bestDistance = distance
                }
            }
            start = best
            placed.append(cumulative[best])
        }
        self.stops = placed
    }

    /// The point `fraction` of the way along the track from stop `from` to stop `to`; `nil` without a usable track.
    func point(between from: Int, and to: Int, fraction: Double) -> (coordinate: Coordinate, bearing: Double?)? {
        guard path.length > 0, to < stops.count, stops[to] > stops[from] else { return nil }
        let distance = stops[from] + (stops[to] - stops[from]) * fraction
        return path.point(atFraction: distance / path.length)
    }
}

public extension DepartureStatus {
    /// How a time stands against the timetable from its delay: cancelled first, then scheduled without realtime
    /// data, uncertain while that data is stale, else late or early by at least ``delayThreshold``, or on time.
    init(delayMinutes: Int?, isRealtime: Bool, isCancelled: Bool, realtimeIsStale: Bool = false) {
        if isCancelled {
            self = .cancelled
        } else if !isRealtime {
            self = .scheduled
        } else if realtimeIsStale {
            self = .uncertain
        } else {
            let delay = delayMinutes ?? 0
            if delay >= Self.delayThreshold {
                self = .late(minutes: delay)
            } else if delay <= -Self.delayThreshold {
                self = .early(minutes: -delay)
            } else {
                self = .onTime
            }
        }
    }

    /// The status in a few characters, for beside a time in a list: "+3 min" late, "−2 min" early, "On time",
    /// "Sched.", "Canc.", or "Not live". English until the app localizes.
    var shortText: String {
        switch self {
        case .scheduled: "Sched."
        case .onTime: "On time"
        case let .late(minutes): "+\(minutes) min"
        case let .early(minutes): "\u{2212}\(minutes) min"
        case .cancelled: "Canc."
        case .uncertain: "Not live"
        }
    }

    /// The status as VoiceOver reads it: "3 minutes late", "2 minutes early", "on time", "scheduled", "cancelled",
    /// or "may not be real time".
    var spokenText: String {
        switch self {
        case .scheduled: "scheduled"
        case .onTime: "on time"
        case let .late(minutes): minutes == 1 ? "1 minute late" : "\(minutes) minutes late"
        case let .early(minutes): minutes == 1 ? "1 minute early" : "\(minutes) minutes early"
        case .cancelled: "cancelled"
        case .uncertain: "may not be real time"
        }
    }
}

/// Itinerary helpers for following one trip.
public extension Itinerary {
    /// The trip's first transit leg: its line, headsign, and colours.
    var tripLeg: Leg? {
        transitLegs.first
    }
}

/// Whether a ``TransitError`` means the trip doesn't exist (any longer), rather than that it couldn't be fetched.
public extension TransitError {
    var isNotFound: Bool {
        if case let .server(statusCode, _) = self {
            return statusCode == 404
        }
        return false
    }
}
