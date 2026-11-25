import Foundation
import Observation
import TransitKit

/// The vehicles of the rides a screen follows, for ``MapView``: the one bus or train each ride is on, and no other.
///
/// A journey's plan or a trip's view hands it the rides it shows (``Target``) and shows what it works out
/// (``SwiftUI/View/rideVehicles(owner:targets:)``). Nothing is fetched or drawn for the home map, search, or journey
/// options, and no bus is looked for until its ride is near (``TrackedRide/isTrackable(at:)``).
///
/// - **Subway trains** are placed from the ride's trip as fetched for the screen (live times, no GPS), and show only
///   where realtime data stands behind them and is under a minute old.
/// - **Buses** are looked for in Bus Time's GPS feed around where the ride should be, about every 30 seconds, by
///   trip id first and only then by route, direction, and place (``TrackedRide/bus(among:at:)``). A bus found goes
///   when its fix, or the feed, is more than a minute old; walks, and rides without a trip id, are never tracked.
///
/// Following different rides starts afresh: what's in flight for the old ones is thrown away when it lands.
@MainActor
@Observable
final class RideVehicles {
    /// A ride to follow, with the trip it's on where the screen has fetched it.
    struct Target: Equatable {
        var ride: TrackedRide
        /// The ride's trip from `client.trip(id:)`, which places a train; `nil` before it's fetched.
        var trip: Itinerary?
        /// When the screen fetched ``trip``, and how old the server's realtime data was then.
        var fetchedAt: Date?
        var dataAge: RealtimeDataAge?
    }

    /// How often vehicles move on and are checked for going stale.
    static let tick: Duration = .seconds(5)
    /// How often Bus Time is asked again: its feed and our server's cache update every 30 seconds.
    static let busRefreshInterval: TimeInterval = 30
    /// How old a bus's own GPS fix may be before it isn't shown.
    static let maximumFixAge: TimeInterval = 120

    /// The vehicles to draw.
    private(set) var vehicles: [MapVehicle] = []

    /// A bus taken for a ride's, as the last fetch found it.
    private struct Fix {
        var bus: Bus
        var fetchedAt: Date
        var feedAge: RealtimeDataAge

        func isFresh(at now: Date) -> Bool {
            now.timeIntervalSince(fetchedAt) <= RealtimeDataAge.realTimeLimit
                && !feedAge.mayNotBeRealTime(at: now)
                && bus.timestamp.map { now.timeIntervalSince($0) <= RideVehicles.maximumFixAge } ?? true
        }
    }

    @ObservationIgnored private var targets: [Target] = []
    /// Bumped as different rides are followed, so a fetch for the old ones is ignored when it lands.
    @ObservationIgnored private var generation = 0
    /// The bus found for each ride, by trip id.
    @ObservationIgnored private var fixes: [String: Fix] = [:]
    /// Each ride's bus as shown last, and its heading, for buses whose fix has no bearing.
    @ObservationIgnored private var previousBuses: [String: Bus] = [:]
    @ObservationIgnored private var headings: [String: Double] = [:]
    @ObservationIgnored private var attemptedAt: Date?
    @ObservationIgnored private var fetch: Task<Void, Never>?
    @ObservationIgnored private var client: TransitClient?
    @ObservationIgnored private var now: @MainActor () -> Date = { .now }

    /// Follows `targets`. The same rides with newer trips keep what's been found; other rides start afresh.
    func track(_ targets: [Target]) {
        let rides = Set(targets.map(\.ride.id))
        if rides != Set(self.targets.map(\.ride.id)) {
            generation += 1
            cancelFetch()
            fixes = [:]
            previousBuses = [:]
            headings = [:]
            attemptedAt = nil
            if !vehicles.isEmpty {
                vehicles = []
            }
        }
        self.targets = targets
    }

    /// Moves vehicles on and asks Bus Time for buses on a timer until cancelled, such as when the app leaves the
    /// foreground.
    ///
    /// - Parameters:
    ///   - client: Where buses come from.
    ///   - now: The current time; the screenshot harness's fixed clock where it runs on fixtures.
    func run(client: TransitClient, now: @escaping @MainActor () -> Date) async {
        self.client = client
        self.now = now
        while !Task.isCancelled {
            refreshBusesIfDue()
            update()
            try? await Task.sleep(for: Self.tick)
        }
        cancelFetch()
        self.client = nil
    }

    private func cancelFetch() {
        fetch?.cancel()
        fetch = nil
    }

    /// Asks Bus Time for the buses around each bus ride that's near, if it's time to.
    private func refreshBusesIfDue() {
        guard let client else { return }
        let start = now()
        let requests: [(ride: TrackedRide, area: CoordinateBounds)] = targets.compactMap { target in
            guard target.ride.mode == .bus,
                  let area = target.ride.busSearchArea(at: start, trip: target.trip)
            else { return nil }
            return (target.ride, area)
        }
        guard !requests.isEmpty, attemptedAt.map({ start.timeIntervalSince($0) >= Self.busRefreshInterval }) ?? true
        else { return }
        cancelFetch()
        attemptedAt = start
        let generation = generation
        fetch = Task {
            let fetched = await withTaskGroup(of: (TrackedRide, BusPositions?).self) { group in
                for request in requests {
                    group.addTask {
                        let positions = try? await client.buses(in: request.area)
                        return (request.ride, positions)
                    }
                }
                var results: [(TrackedRide, BusPositions?)] = []
                for await result in group {
                    results.append(result)
                }
                return results
            }
            // The rides have changed, or the screen has gone: these buses are for something else.
            guard !Task.isCancelled, generation == self.generation else { return }
            let landed = now()
            for (ride, positions) in fetched {
                // A failed fetch keeps the bus it found before, which goes once it's a minute old.
                guard let positions else { continue }
                let match = ride.bus(among: positions.vehicles, at: landed)
                if let match, let shown = fixes[ride.id]?.bus {
                    previousBuses[ride.id] = shown
                }
                fixes[ride.id] = match.map { Fix(bus: $0.bus, fetchedAt: start, feedAge: positions.dataAge) }
            }
            fetch = nil
            update()
        }
    }

    /// Works out the vehicles to show now.
    private func update() {
        let now = now()
        var vehicles: [MapVehicle] = []
        for target in targets {
            let ride = target.ride
            if ride.mode == .bus {
                guard ride.isTrackable(at: now), let fix = fixes[ride.id], fix.isFresh(at: now) else { continue }
                let heading = fix.bus.heading(
                    after: previousBuses[ride.id].flatMap { $0.id == fix.bus.id ? $0 : nil },
                    previousHeading: headings[ride.id]
                )
                headings[ride.id] = heading
                vehicles.append(MapVehicle(ride: ride, bus: fix.bus, heading: heading))
            } else if let trip = target.trip, let fetchedAt = target.fetchedAt,
                      now.timeIntervalSince(fetchedAt) <= RealtimeDataAge.realTimeLimit,
                      target.dataAge?.mayNotBeRealTime(at: now) == false,
                      let position = ride.estimatedPosition(in: trip, at: now)
            {
                vehicles.append(MapVehicle(ride: ride, estimate: position))
            }
        }
        if vehicles != self.vehicles {
            self.vehicles = vehicles
        }
    }
}
