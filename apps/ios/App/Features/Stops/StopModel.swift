import Foundation
import Observation
import TransitKit

/// The departures board behind a stop's screen: fetches every upcoming departure at the stop, with the server's
/// realtime data age, and refreshes them about every 30 seconds while ``run(client:stopId:now:)`` runs. The screen
/// starts and stops that with its `.task`, so refreshing pauses while it isn't visible.
@MainActor
@Observable
final class StopModel {
    /// What the board holds.
    enum Content: Equatable {
        /// Nothing fetched yet.
        case idle
        /// The first fetch is under way.
        case loading
        case loaded(StopBoard)
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

    /// How often the board refreshes while visible.
    static let refreshInterval = Duration.seconds(30)
    /// The modes Express v1 covers.
    static let modes: [TransitMode] = [.subway, .bus]

    /// Refreshes the board now, then about every ``refreshInterval`` until the calling task is cancelled.
    func run(client: TransitClient, stopId: String, now: () -> Date) async {
        while !Task.isCancelled {
            await refresh(client: client, stopId: stopId, now: now())
            try? await Task.sleep(for: Self.refreshInterval)
        }
    }

    /// Fetches the board once. A failure keeps the board already shown, which then reads as not real time once it's
    /// a minute old (``StopBoard/mayNotBeRealTime(at:)``).
    func refresh(client: TransitClient, stopId: String, now: Date) async {
        self.now = now
        if !content.isLoaded {
            content = .loading
        }
        do throws(TransitError) {
            async let age = client.realtimeDataAge()
            let response = try await client.departures(StopBoard.request(stopId: stopId, modes: Self.modes))
            // An unknown age reads as not real time, which is what the notice should then say.
            let dataAge = await (try? age) ?? RealtimeDataAge(feedTimestamp: nil)
            guard !Task.isCancelled else { return }
            content = .loaded(StopBoard(stopTimes: response.stopTimes, fetchedAt: now, dataAge: dataAge))
        } catch {
            guard !Task.isCancelled, !content.isLoaded else { return }
            content = .failed(error)
        }
    }
}
