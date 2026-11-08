import Foundation
import Observation
import TransitKit

/// The departures board behind the Nearby section: finds the stops near a location, fetches their departures and
/// the server's realtime data age, and refreshes them about every 30 seconds while ``run(client:location:now:)``
/// runs. The section starts and stops that with its `.task`, so refreshing pauses while it isn't visible.
@MainActor
@Observable
final class NearbyModel {
    /// What the board holds.
    enum Content: Equatable {
        /// Nothing fetched yet.
        case idle
        /// The first fetch is under way.
        case loading
        case loaded(NearbyBoard)
        /// The last fetch failed with nothing fetched before it to fall back on.
        case failed(TransitError)

        var isLoaded: Bool {
            if case .loaded = self {
                true
            } else {
                false
            }
        }
    }

    private(set) var content = Content.idle
    /// The time the countdowns count from, updated on every refresh.
    private(set) var now = Date.now

    /// The stops found around ``stopsCenter``, kept until the rider moves ``stopsRadius`` away from it.
    private var stops: [NearbyStop] = []
    private var stopsCenter: Coordinate?

    /// How often the board refreshes while visible.
    static let refreshInterval = Duration.seconds(30)
    /// How far the rider may move before the stops are looked up again, in metres.
    static let stopsRadius: Double = 100
    /// Half the side of the box searched for stops, in degrees of latitude (about 550 m).
    static let searchSpan = 0.005
    /// How many stops the board lists.
    static let stopLimit = 5
    /// The modes Express v1 covers.
    static let modes: [TransitMode] = [.subway, .bus]

    /// Refreshes the board now, then about every ``refreshInterval`` until the calling task is cancelled.
    /// Each refresh reads the latest `location()` and `now()`; it skips a refresh while the location is unknown.
    func run(client: TransitClient, location: () -> Coordinate?, now: () -> Date) async {
        while !Task.isCancelled {
            if let fix = location() {
                await refresh(client: client, location: fix, now: now())
            }
            try? await Task.sleep(for: Self.refreshInterval)
        }
    }

    /// Fetches the board once. A failure keeps the board already shown, which then reads as not real time once it's
    /// a minute old (``NearbyBoard/mayNotBeRealTime(at:)``).
    func refresh(client: TransitClient, location: Coordinate, now: Date) async {
        self.now = now
        if !content.isLoaded {
            content = .loading
        }
        do {
            let board = try await fetchBoard(client: client, location: location, now: now)
            guard !Task.isCancelled else { return }
            content = .loaded(board)
        } catch {
            guard !Task.isCancelled, !content.isLoaded else { return }
            content = .failed(error)
        }
    }

    private func fetchBoard(
        client: TransitClient,
        location: Coordinate,
        now: Date
    ) async throws(TransitError) -> NearbyBoard {
        async let age = client.realtimeDataAge()
        let stops = try await nearbyStops(client: client, location: location)
        let departures = try await Self.departures(at: stops, client: client)
        // An unknown age reads as not real time, which is what the notice should then say.
        let dataAge = await (try? age) ?? RealtimeDataAge(feedTimestamp: nil)
        return NearbyBoard(stops: stops, departures: departures, fetchedAt: now, dataAge: dataAge)
    }

    /// The stops near `location`, looked up again only once the rider has moved ``stopsRadius`` away.
    private func nearbyStops(client: TransitClient, location: Coordinate) async throws(TransitError) -> [NearbyStop] {
        if let stopsCenter, stopsCenter.distance(to: location) < Self.stopsRadius {
            return stops
        }
        // A box about as wide as it is tall: a degree of longitude is shorter than one of latitude here.
        let lonSpan = Self.searchSpan / cos(location.latitude * .pi / 180)
        let found = try await client.stops(
            southWest: Coordinate(
                latitude: location.latitude - Self.searchSpan,
                longitude: location.longitude - lonSpan
            ),
            northEast: Coordinate(
                latitude: location.latitude + Self.searchSpan,
                longitude: location.longitude + lonSpan
            ),
            transitModes: Self.modes
        )
        stops = found.nearbyStops(around: location, limit: Self.stopLimit)
        stopsCenter = location
        return stops
    }

    /// Each stop's departures over the next half hour (at least ten), fetched together. A stop whose request fails
    /// shows nothing; only when every one fails does the board fail.
    private static func departures(
        at stops: [NearbyStop],
        client: TransitClient
    ) async throws(TransitError) -> [String: [Departure]] {
        let modes = Self.modes
        let results = await withTaskGroup(of: (String, Result<[Departure], TransitError>).self) { group in
            for stop in stops {
                group.addTask {
                    let request = DeparturesRequest(stopId: stop.id, count: 10, window: 30 * 60, transitModes: modes)
                    do throws(TransitError) {
                        let response = try await client.departures(request)
                        return (stop.id, .success(response.stopTimes))
                    } catch {
                        return (stop.id, .failure(error))
                    }
                }
            }
            var results: [String: Result<[Departure], TransitError>] = [:]
            for await (id, result) in group {
                results[id] = result
            }
            return results
        }
        var departures: [String: [Departure]] = [:]
        var firstError: TransitError?
        for (id, result) in results {
            switch result {
            case let .success(stopTimes): departures[id] = stopTimes
            case let .failure(error): firstError = firstError ?? error
            }
        }
        if departures.isEmpty, !stops.isEmpty, let firstError {
            throw firstError
        }
        return departures
    }
}
