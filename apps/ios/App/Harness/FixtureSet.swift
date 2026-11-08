import Foundation
import TransitKit

/// A named, deterministic set of data for the app to show instead of live data, selected with `-fixtures <name>`.
/// Add a case for a new scenario; fixture-backed data clients switch over it to decide what to return.
enum FixtureSet: String, CaseIterable, Sendable {
    /// Weekday evening rush in Manhattan: departures at Union Square and the stops around it, live and scheduled.
    case nycEvening = "nyc-evening"
    /// The same evening, with the server's realtime data three minutes old, so times may not be real time.
    case nycEveningStale = "nyc-evening-stale"
    /// The same stops with nothing due at any of them.
    case nycNoService = "nyc-no-service"
    /// The evening rush on a network so slow that nothing comes back, so screens hold their loading state.
    case slowNetwork = "slow-network"
    /// The evening rush with no network: every request fails as offline.
    case offline
    /// The evening rush in a build with no Google Maps key, so place search is unavailable.
    case noKey = "no-key"

    /// The moment the fixtures describe, which stands in for "now" so times on screen don't drift between runs.
    var referenceDate: Date {
        switch self {
        case .nycEvening, .nycEveningStale, .nycNoService, .slowNetwork, .offline, .noKey:
            Date(timeIntervalSince1970: 1_793_748_600) // 2026-11-03 18:30 America/New_York
        }
    }

    /// Where the rider stands in the fixtures: the south-east corner of Union Square, by the 4, 5, and 6.
    static let unionSquare = Coordinate(latitude: 40.7343, longitude: -73.9895)

    /// How old the server's realtime data is at ``referenceDate``.
    var realtimeDataAge: TimeInterval {
        self == .nycEveningStale ? 180 : 15
    }
}
