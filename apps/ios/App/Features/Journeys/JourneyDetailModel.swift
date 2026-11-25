import Foundation
import Observation
import TransitKit

/// The journey detail screen's state: the itinerary tapped, kept live by fetching the trips its rides are on about
/// every 30 seconds while ``run(client:now:)`` runs (``TransitClient/refreshRides(of:)``), with the server's realtime
/// data age.
///
/// A route has several departures: the one open, the others the planner offered, and, for a ride with no changes, the
/// next trips of its line found from its boarding stop (``TransitClient/upcomingTrips(like:excluding:after:limit:)``,
/// once, each checked against its own trip). ``select(_:)`` switches between them.
///
/// It follows the trips rather than planning again: a trip stays the same trip however the rider's location or the
/// clock moves, and its live times say when a ride is late, cancelled, or no longer makes its connection.
@MainActor
@Observable
final class JourneyDetailModel {
    /// How often the rides refresh while the plan shows.
    static let refreshInterval: Duration = .seconds(30)

    /// The most departures of a route the plan offers to pick between.
    static let maximumDepartures = 5

    private(set) var itinerary: Itinerary
    private(set) var plan: JourneyPlan
    /// Every departure of the route on offer, soonest first, the open one among them. Each is a whole journey that
    /// works: planned by MOTIS, or the same ride on another trip checked against that trip.
    private(set) var departures: [Itinerary]
    private let findsMoreDepartures: Bool
    private var hasFoundMore = false
    /// When the rides last came back from the server; nil before the first refresh.
    private(set) var refreshedAt: Date?
    /// How old the server's realtime feeds were at the last refresh; nil where unknown.
    private(set) var dataAge: RealtimeDataAge?
    /// Whether the first refresh has finished, well or not.
    private(set) var hasRefreshed = false
    /// When the plan first showed, which stands in for the last refresh until there is one.
    private var openedAt: Date?

    init(itinerary: Itinerary, alternatives: [Itinerary] = [], findsMoreDepartures: Bool = false) {
        self.itinerary = itinerary
        plan = JourneyPlan(itinerary)
        self.findsMoreDepartures = findsMoreDepartures
        departures = Self.sorted([itinerary], adding: alternatives)
    }

    /// The departures still to leave at `now` (a minute's grace, as the options list gives), as summaries, soonest
    /// first: the open one always stays.
    func upcomingDepartures(at now: Date) -> [JourneySummary] {
        departures.compactMap { departure in
            let summary = JourneySummary(departure)
            let leaves = summary.firstRideDeparture ?? summary.departure
            return departure.id == itinerary.id || leaves >= now.addingTimeInterval(-60) ? summary : nil
        }
    }

    /// Opens another of the route's departures, by its id.
    func select(_ id: String) {
        guard id != itinerary.id, let next = departures.first(where: { $0.id == id }) else { return }
        itinerary = next
        plan = JourneyPlan(next)
    }

    private static func sorted(_ departures: [Itinerary], adding more: [Itinerary]) -> [Itinerary] {
        var seen = Set<String>()
        return (departures + more)
            .filter { seen.insert($0.id).inserted }
            .sorted { lhs, rhs in
                let left = JourneySummary(lhs)
                let right = JourneySummary(rhs)
                return (left.firstRideDeparture ?? left.departure) < (right.firstRideDeparture ?? right.departure)
            }
    }

    /// Fills the route's departures up to ``maximumDepartures`` with the next trips of its line, once: for a ride with
    /// no changes only, checking each against its own trip, so what's added is a journey that works. Nothing where the
    /// server can't answer.
    func findMoreDepartures(client: TransitClient) async {
        let wanted = Self.maximumDepartures - departures.count
        guard findsMoreDepartures, !hasFoundMore, wanted > 0, let first = departures.first else { return }
        let summary = JourneySummary(first)
        let more = await client.upcomingTrips(
            like: first,
            excluding: Set(departures.flatMap { JourneySummary($0).tripIDs }),
            after: summary.firstRideDeparture ?? summary.departure,
            limit: wanted
        )
        guard !Task.isCancelled else { return }
        hasFoundMore = true
        departures = Self.sorted(departures, adding: more)
    }

    /// Refreshes the rides now, then again every ``refreshInterval`` until the calling task is cancelled, which
    /// happens as the plan goes away or the app leaves the foreground.
    func run(client: TransitClient, now: @escaping () -> Date) async {
        if openedAt == nil {
            openedAt = now()
        }
        async let moreDepartures: Void = findMoreDepartures(client: client)
        while !Task.isCancelled {
            await refresh(client: client, now: now)
            try? await Task.sleep(for: Self.refreshInterval)
        }
        await moreDepartures
    }

    /// Fetches the rides' trips once. A failure keeps the times already shown, which then read as not real time once
    /// they're a minute old.
    func refresh(client: TransitClient, now: () -> Date) async {
        async let age = try? client.realtimeDataAge()
        // The departure open as the refresh starts: the rider may pick another before it comes back.
        let target = itinerary
        let refreshed: Itinerary?
        do throws(TransitError) {
            refreshed = try await client.refreshRides(of: target)
        } catch {
            refreshed = nil
        }
        let latestAge = await age
        guard !Task.isCancelled else { return }
        hasRefreshed = true
        guard let refreshed else { return }
        if refreshed != target {
            if let index = departures.firstIndex(where: { $0.id == refreshed.id }) {
                departures[index] = refreshed
            }
            if itinerary.id == refreshed.id {
                itinerary = refreshed
                plan = JourneyPlan(refreshed)
            }
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
