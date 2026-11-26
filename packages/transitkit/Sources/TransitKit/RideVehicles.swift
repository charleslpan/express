import Foundation

// Which vehicle is the one a rider's ride is on, for the map to show it and no other: the trip's own bus by its trip
// id, a bus that can only be it by route, direction, and place, or a train placed from the trip's live times.

/// A ride on one transit trip that the map may show the vehicle of: a leg of a planned journey, or a trip opened from
/// a departure.
///
/// Walks and legs without a trip id are never rides, so they have no vehicle; nor is a cancelled trip, or a mode with
/// no live source (the subway's trains come from the trip's live times, buses from Bus Time's GPS).
public struct TrackedRide: Sendable, Hashable, Identifiable {
    /// How long before boarding a ride's vehicle starts to show, and so to be looked for.
    public static let leadTime: TimeInterval = 30 * 60
    /// How far a bus without a trip id may be from the ride's track and still be taken for its bus, in metres.
    public static let maximumDistanceFromPath: Double = 100
    /// How far a bus without a trip id may be from where the timetable puts the ride, in seconds.
    public static let maximumScheduleOffset: TimeInterval = 180
    /// How far around where the ride should be to look for its bus, in degrees (about 1.7 km north to south).
    static let searchMargin = 0.015

    /// The trip's id, as MOTIS gives it (`20261125_13:15_us-ny-MTA-BusManhattan_OF_D6-Weekday-SDon-079500_M7_213`).
    public var tripId: String
    public var mode: TransitMode
    public var bullet: LineBullet
    /// The GTFS `route_id` Bus Time's feed uses (`M14A+`), from MOTIS's route id without its dataset prefix.
    public var route: String?
    /// The GTFS `direction_id`, 0 or 1, where the ride has one.
    public var directionId: Int?
    /// The ride's track.
    public var path: [Coordinate]
    /// When the ride sets off (its boarding time) and ends (its alighting time).
    public var start: Date
    public var end: Date

    public var id: String {
        tripId
    }

    /// The ride a leg is, or `nil` for a walk, a leg with no trip id, a cancelled trip, or a mode with no live source.
    public init?(leg: Leg) {
        guard let tripId = leg.tripId, !tripId.isEmpty, leg.cancelled != true, let bullet = leg.lineBullet,
              leg.mode == .subway || leg.mode == .bus
        else { return nil }
        self.tripId = tripId
        mode = leg.mode
        self.bullet = bullet
        route = leg.routeId.flatMap { id in
            id.firstIndex(of: "_").map { String(id[id.index(after: $0)...]) }
        }
        directionId = leg.directionId.flatMap { Int($0) }
        path = leg.coordinates
        start = leg.startTime
        end = leg.endTime
    }

    /// The ride a trip is as a whole, from its first stop to its last (`client.trip(id:)`).
    public init?(trip: Itinerary) {
        guard let leg = trip.tripLeg else { return nil }
        self.init(leg: leg)
    }

    /// Whether the ride's vehicle is worth showing at `now`: from ``leadTime`` before boarding until the rider
    /// gets off.
    public func isTrackable(at now: Date) -> Bool {
        now >= start.addingTimeInterval(-Self.leadTime) && now <= end
    }

    /// The bus's trip id as the bus feed spells it: MOTIS's id is the feed's after the date, time, and dataset
    /// (`20261125_13:15_us-ny-MTA-BusManhattan_` before `OF_D6-Weekday-SDon-079500_M7_213`); `nil` for an id that isn't
    /// spelled that way.
    public static func feedTripId(fromMOTIS id: String) -> String? {
        let parts = id.split(separator: "_", maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0].count == 8, parts[0].allSatisfy(\.isNumber), parts[1].contains(":"),
              !parts[3].isEmpty
        else { return nil }
        return String(parts[3])
    }

    // MARK: Buses

    /// How a bus came to be taken for the ride's.
    public enum Evidence: Sendable, Hashable {
        /// The bus reports this very trip.
        case tripId
        /// The bus reports no trip, but runs the ride's route and direction, along its track, where its timetable
        /// has it.
        case routeDirectionAndPlace
    }

    /// The ride's bus, among the buses Bus Time reports.
    ///
    /// The bus that reports the ride's trip id wins. Only where none does, a bus that reports **no** trip may stand
    /// in for it, if it runs the ride's route in its direction (both known), is within ``maximumDistanceFromPath`` of
    /// the ride's track, and is where the timetable puts the ride, give or take ``maximumScheduleOffset``; the
    /// nearest to the timetable is the one. A bus that reports another trip is never the ride's. Subway rides have no
    /// bus.
    public func bus(among buses: [Bus], at now: Date) -> (bus: Bus, evidence: Evidence)? {
        guard mode == .bus else { return nil }
        if let feedId = Self.feedTripId(fromMOTIS: tripId) {
            let reporting = buses.filter { $0.tripId == feedId }
            if let exact = reporting.max(by: { ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast) }) {
                return (exact, .tripId)
            }
        }
        guard let route, let directionId, end > start, path.count >= 2 else { return nil }
        let track = PolylinePath(path)
        let duration = end.timeIntervalSince(start)
        var best: (bus: Bus, offset: TimeInterval)?
        for bus in buses where (bus.tripId ?? "").isEmpty && bus.route == route && bus.directionId == directionId {
            guard let near = track.nearest(to: bus.coordinate), near.distance <= Self.maximumDistanceFromPath else {
                continue
            }
            let timetabled = start.addingTimeInterval(near.fraction * duration)
            let offset = abs(timetabled.timeIntervalSince(now))
            if offset <= Self.maximumScheduleOffset, best.map({ offset < $0.offset }) ?? true {
                best = (bus, offset)
            }
        }
        return best.map { ($0.bus, .routeDirectionAndPlace) }
    }

    /// The area to ask Bus Time for, around where the ride should be now; `nil` where it isn't trackable.
    ///
    /// - Parameter trip: The ride's trip as fetched, whose live times place the vehicle better than the timetable.
    public func busSearchArea(at now: Date, trip: Itinerary? = nil) -> CoordinateBounds? {
        guard isTrackable(at: now), let center = expectedCoordinate(at: now, trip: trip) else { return nil }
        return CoordinateBounds(
            southWest: Coordinate(
                latitude: center.latitude - Self.searchMargin,
                longitude: center.longitude - Self.searchMargin
            ),
            northEast: Coordinate(
                latitude: center.latitude + Self.searchMargin,
                longitude: center.longitude + Self.searchMargin
            )
        )
    }

    /// Where the ride's vehicle should be at `now`: where the trip's live times put it, else along the track in
    /// proportion to the time between boarding and alighting; the first point before boarding.
    public func expectedCoordinate(at now: Date, trip: Itinerary? = nil) -> Coordinate? {
        if let trip {
            let progress = TripProgress(trip: trip, at: now)
            if let coordinate = progress.vehicle?.coordinate ?? progress.nextStop?.place.coordinate {
                return coordinate
            }
        }
        let duration = end.timeIntervalSince(start)
        let fraction = duration > 0 ? now.timeIntervalSince(start) / duration : 0
        return PolylinePath(path).point(atFraction: fraction)?.coordinate
    }

    // MARK: Trains

    /// Where the ride's vehicle is estimated to be, from `trip`'s live times (`client.trip(id:)`): the subway has no
    /// GPS. `nil` unless the ride is trackable at `now`, the vehicle is running, and realtime data stands behind the
    /// times around it, so a train that only the timetable says is running never shows.
    public func estimatedPosition(in trip: Itinerary, at now: Date) -> EstimatedPosition? {
        guard isTrackable(at: now) else { return nil }
        let progress = TripProgress(trip: trip, at: now)
        guard progress.phase == .running, let vehicle = progress.vehicle,
              progress.stops[vehicle.fromIndex].isRealtime || progress.stops[vehicle.toIndex].isRealtime
        else { return nil }
        return EstimatedPosition(
            coordinate: vehicle.coordinate,
            bearing: vehicle.bearing,
            fromStop: progress.stops[vehicle.fromIndex].name,
            toStop: progress.stops[vehicle.toIndex].name
        )
    }

    /// A vehicle's estimated place between two stops.
    public struct EstimatedPosition: Sendable, Hashable {
        public var coordinate: Coordinate
        /// The direction of travel, in degrees clockwise from north.
        public var bearing: Double
        public var fromStop: String
        /// The stop it runs to next; the same as ``fromStop`` while it stands at one.
        public var toStop: String
    }
}

public extension TransitClient {
    /// The trips of an itinerary's rides, by trip id, fetched at once: what ``refreshRides(of:)`` brings the rides up
    /// to date from, and what places a train between its stops.
    ///
    /// A trip that can't be fetched is left out; it throws only where every trip fails, with the first failure. A
    /// journey on foot has none.
    func rideTrips(of itinerary: Itinerary) async throws(TransitError) -> [String: Itinerary] {
        let tripIds = Array(Set(itinerary.transitLegs.compactMap(\.tripId)))
        guard !tripIds.isEmpty else { return [:] }
        let results = await withTaskGroup(of: (String, Result<Itinerary, TransitError>).self) { group in
            for id in tripIds {
                group.addTask {
                    do throws(TransitError) {
                        return try await (id, .success(trip(id: id)))
                    } catch {
                        return (id, .failure(error))
                    }
                }
            }
            var results: [String: Result<Itinerary, TransitError>] = [:]
            for await (id, result) in group {
                results[id] = result
            }
            return results
        }
        let trips = results.compactMapValues { try? $0.get() }
        if trips.isEmpty, let failure = tripIds.lazy.compactMap({ id -> TransitError? in
            if case let .failure(error) = results[id] {
                error
            } else {
                nil
            }
        }).first {
            throw failure
        }
        return trips
    }
}
