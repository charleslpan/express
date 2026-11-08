import Foundation

/// A named, deterministic set of data for the app to show instead of live data, selected with `-fixtures <name>`.
/// Add a case for a new scenario; fixture-backed data clients switch over it to decide what to return.
enum FixtureSet: String, CaseIterable, Sendable {
    /// Weekday evening rush in Manhattan.
    case nycEvening = "nyc-evening"
    /// The evening rush on a network so slow that nothing comes back, so screens hold their loading state.
    case slowNetwork = "slow-network"
    /// The evening rush with no network: every request fails as offline.
    case offline
    /// The evening rush in a build with no Google Maps key, so place search is unavailable.
    case noKey = "no-key"
    /// The evening rush, with no journey to be found anywhere.
    case noJourneys = "no-journeys"
    /// The evening rush, with the server's realtime feeds five minutes old, so times may not be real time.
    case staleData = "stale-data"

    /// The moment the fixtures describe, which stands in for "now" so times on screen don't drift between runs.
    var referenceDate: Date {
        switch self {
        case .nycEvening, .slowNetwork, .offline, .noKey, .noJourneys, .staleData:
            Date(timeIntervalSince1970: 1_793_748_600) // 2026-11-03 18:30 America/New_York
        }
    }
}
