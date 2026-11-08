import Foundation
import Observation
import TransitKit

/// The journey detail screen's state: the itinerary tapped, kept live by fetching the trips its rides are on about
/// every 30 seconds while ``run(client:now:)`` runs (``TransitClient/refreshRides(of:)``), with the server's realtime
/// data age.
///
/// It follows the trips rather than planning again: a trip stays the same trip however the rider's location or the
/// clock moves, and its live times say when a ride is late, cancelled, or no longer makes its connection.
@MainActor
@Observable
final class JourneyDetailModel {
    /// How often the rides refresh while the plan shows.
    static let refreshInterval: Duration = .seconds(30)

    private(set) var itinerary: Itinerary
    private(set) var plan: JourneyPlan
    /// When the rides last came back from the server; nil before the first refresh.
    private(set) var refreshedAt: Date?
    /// How old the server's realtime feeds were at the last refresh; nil where unknown.
    private(set) var dataAge: RealtimeDataAge?
    /// Whether the first refresh has finished, well or not.
    private(set) var hasRefreshed = false
    /// When the plan first showed, which stands in for the last refresh until there is one.
    private var openedAt: Date?

    init(itinerary: Itinerary) {
        self.itinerary = itinerary
        plan = JourneyPlan(itinerary)
    }

    /// Refreshes the rides now, then again every ``refreshInterval`` until the calling task is cancelled, which
    /// happens as the plan goes away or the app leaves the foreground.
    func run(client: TransitClient, now: @escaping () -> Date) async {
        if openedAt == nil {
            openedAt = now()
        }
        while !Task.isCancelled {
            await refresh(client: client, now: now)
            try? await Task.sleep(for: Self.refreshInterval)
        }
    }

    /// Fetches the rides' trips once. A failure keeps the times already shown, which then read as not real time once
    /// they're a minute old.
    func refresh(client: TransitClient, now: () -> Date) async {
        async let age = try? client.realtimeDataAge()
        let refreshed: Itinerary?
        do throws(TransitError) {
            refreshed = try await client.refreshRides(of: itinerary)
        } catch {
            refreshed = nil
        }
        let latestAge = await age
        guard !Task.isCancelled else { return }
        hasRefreshed = true
        guard let refreshed else { return }
        if refreshed != itinerary {
            itinerary = refreshed
            plan = JourneyPlan(refreshed)
        }
        refreshedAt = now()
        dataAge = latestAge
    }

    /// Whether the plan must say its times may not be real time, as the MTA's terms require: no refresh has come
    /// back for over a minute, or the server's realtime data is more than a minute old (or of unknown age).
    func mayNotBeRealTime(at now: Date) -> Bool {
        guard !plan.rides.isEmpty, let since = refreshedAt ?? openedAt else { return false }
        if now.timeIntervalSince(since) > RealtimeDataAge.realTimeLimit {
            return true
        }
        guard refreshedAt != nil else { return false }
        return dataAge?.mayNotBeRealTime(at: now) ?? true
    }
}
