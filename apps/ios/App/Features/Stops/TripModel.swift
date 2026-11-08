import Foundation
import Observation
import TransitKit

/// The trip behind a trip view: fetches the trip's stops, live times, and track from MOTIS's trip endpoint, with the
/// server's realtime data age, and refreshes them about every 30 seconds while ``run(client:tripId:now:)`` runs.
/// Between fetches it moves the vehicle on every few seconds, so the screen follows it stop by stop.
@MainActor
@Observable
final class TripModel {
    /// What the view holds.
    enum Content: Equatable {
        /// Nothing fetched yet.
        case idle
        /// The first fetch is under way.
        case loading
        case loaded(Itinerary, fetchedAt: Date, dataAge: RealtimeDataAge)
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
    /// The time the trip's progress is worked out at, moved on every ``tick``.
    private(set) var now = Date.now

    /// How often the trip is fetched again while visible.
    static let refreshInterval: TimeInterval = 30
    /// How often the vehicle moves on between fetches.
    static let tick = Duration.seconds(5)

    /// Fetches the trip now and about every ``refreshInterval`` after, moving the vehicle on every ``tick``, until
    /// the calling task is cancelled.
    func run(client: TransitClient, tripId: String, now: () -> Date) async {
        var fetchedAt: Date?
        while !Task.isCancelled {
            let time = now()
            if let fetchedAt, time.timeIntervalSince(fetchedAt) < Self.refreshInterval {
                if time != self.now {
                    self.now = time
                }
            } else {
                await refresh(client: client, tripId: tripId, now: time)
                fetchedAt = time
            }
            try? await Task.sleep(for: Self.tick)
        }
    }

    /// Fetches the trip once. A failure keeps the trip already shown, which then reads as not real time once it's a
    /// minute old.
    func refresh(client: TransitClient, tripId: String, now: Date) async {
        self.now = now
        if !content.isLoaded {
            content = .loading
        }
        do throws(TransitError) {
            async let age = client.realtimeDataAge()
            let trip = try await client.trip(id: tripId)
            let dataAge = await (try? age) ?? RealtimeDataAge(feedTimestamp: nil)
            guard !Task.isCancelled else { return }
            content = .loaded(trip, fetchedAt: now, dataAge: dataAge)
        } catch {
            guard !Task.isCancelled, !content.isLoaded else { return }
            content = .failed(error)
        }
    }
}

extension TripModel.Content {
    /// Whether screens must say times may not be real time at `now`: the trip was fetched over a minute ago, or the
    /// server's realtime data was older than that, or of unknown age, when it was.
    func mayNotBeRealTime(at now: Date) -> Bool {
        guard case let .loaded(_, fetchedAt, dataAge) = self else { return false }
        return now.timeIntervalSince(fetchedAt) > RealtimeDataAge.realTimeLimit || dataAge.mayNotBeRealTime(at: now)
    }
}
