import Foundation
import Observation
import TransitKit

/// The journey options screen's state: the journey asked for, and what planning it gave, refreshed every 30 seconds
/// while the list shows (``run(client:location:now:)``).
@MainActor
@Observable
final class JourneyPlanner {
    /// What the list shows.
    enum Status: Equatable {
        /// Waiting for the device's first location fix.
        case locating
        case loading
        case options([JourneyOption])
        /// MOTIS found no way there at that time.
        case noJourneys
        /// One end lies outside New York City.
        case outsideServiceArea
        /// The journey starts or ends at the current location, and Express may not use it.
        case locationOff(LocationService.Authorization)
        case failed(TransitError)
    }

    /// How often live times refresh while the list shows.
    static let refreshInterval: Duration = .seconds(30)

    var query: JourneyQuery
    private(set) var status = Status.loading
    /// When the options last came back from the server.
    private(set) var updatedAt: Date?
    /// How old the server's realtime feeds were at the last refresh; nil where unknown.
    private(set) var dataAge: RealtimeDataAge?
    /// The query the options shown were planned for.
    private var plannedQuery: JourneyQuery?

    init(query: JourneyQuery) {
        self.query = query
    }

    /// The options, while there are some.
    var options: [JourneyOption] {
        if case let .options(options) = status {
            options
        } else {
            []
        }
    }

    /// Whether the list must say its times may not be real time, as the MTA's terms require: the options are more
    /// than a minute old, or the server's realtime data is (or its age is unknown).
    func mayNotBeRealTime(at now: Date) -> Bool {
        guard !options.isEmpty else { return false }
        if let updatedAt, now.timeIntervalSince(updatedAt) > RealtimeDataAge.realTimeLimit {
            return true
        }
        return dataAge?.mayNotBeRealTime(at: now) ?? true
    }

    /// Plans the journey, then plans it again every ``refreshInterval`` until the calling task is cancelled, which
    /// happens as the list goes away or the query changes.
    func run(client: TransitClient, location: LocationService, now: @escaping () -> Date) async {
        while !Task.isCancelled {
            await load(client: client, location: location, now: now)
            try? await Task.sleep(for: Self.refreshInterval)
        }
    }

    private func load(client: TransitClient, location: LocationService, now: () -> Date) async {
        guard let request = request(location: location) else { return }

        // A refresh of the same journey keeps its options on screen; a new journey starts from loading.
        let planning = query
        if plannedQuery != planning || options.isEmpty {
            status = .loading
        }
        async let age = try? client.realtimeDataAge()
        let result: Result<PlanResponse, TransitError>
        do throws(TransitError) {
            result = try await .success(client.plan(request))
        } catch {
            result = .failure(error)
        }
        let latestAge = await age
        guard !Task.isCancelled, planning == query else { return }
        show(result, for: planning, dataAge: latestAge, now: now())
    }

    /// The request for ``query`` from the device's location; nil, with the status saying why, where there's none yet.
    private func request(location: LocationService) -> PlanRequest? {
        if query.needsCurrentLocation {
            switch location.authorization {
            case .denied, .restricted:
                status = .locationOff(location.authorization)
                return nil
            case .notDetermined:
                status = .locating
                return nil
            case .authorized:
                break
            }
        }
        do throws(JourneyQueryError) {
            return try query.planRequest(currentLocation: location.location)
        } catch .locationUnknown {
            status = .locating
        } catch {
            status = .outsideServiceArea
        }
        return nil
    }

    private func show(
        _ result: Result<PlanResponse, TransitError>,
        for planning: JourneyQuery,
        dataAge: RealtimeDataAge?,
        now: Date
    ) {
        switch result {
        case let .success(response):
            let options = JourneyOptions.options(from: response, for: planning.time, now: now)
            status = options.isEmpty ? .noJourneys : .options(options)
            plannedQuery = planning
            updatedAt = now
            self.dataAge = dataAge
        case .failure(.noRoute):
            status = .noJourneys
            plannedQuery = planning
        case let .failure(error):
            // A failed refresh keeps the options it had; they turn "may not be real time" after a minute.
            if plannedQuery != planning || options.isEmpty {
                status = .failed(error)
            }
        }
    }

    /// The option to draw on the map after the options change: `current` where it's still offered (by id, or by
    /// the trips it rides, since a refresh can change an itinerary's id), else the first.
    func selection(keeping current: Itinerary?) -> Itinerary? {
        guard let first = options.first else { return nil }
        guard let current else { return first.itinerary }
        let trips = JourneySummary(current).tripIDs
        let kept = options.first { $0.id == current.id }
            ?? options.first { !trips.isEmpty && $0.summary.tripIDs == trips }
        return (kept ?? first).itinerary
    }
}
