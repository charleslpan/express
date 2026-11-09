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
    /// The same evening's buses with no trains running, so the map shows buses alone.
    case nycEveningBuses = "nyc-evening-buses"
    /// Buses alone, with Bus Time's feed three minutes old, so the map says bus positions may not be real time.
    case nycEveningBusesStale = "nyc-evening-buses-stale"
    /// The evening rush, with no journey to be found anywhere.
    case noJourneys = "no-journeys"
    /// The evening rush with the uptown 6 the journeys ride (`fixture-trip-6`) cancelled on live times.
    case nycEveningCancelled = "nyc-evening-cancelled"
    /// The same evening with service alerts (A3): the L suspended in Brooklyn and uptown 4s delayed, both now, and
    /// night work on the 6 two weeks away that must not show yet, on Nearby's departures; and the MTA's alerts as
    /// recorded that evening for line status.
    case nycAlerts = "nyc-alerts"

    /// The moment the fixtures describe, which stands in for "now" so times on screen don't drift between runs.
    var referenceDate: Date {
        switch self {
        case .nycEvening, .nycEveningStale, .nycNoService, .nycEveningBuses, .nycEveningBusesStale, .slowNetwork,
             .offline, .noKey, .noJourneys, .nycEveningCancelled, .nycAlerts:
            Date(timeIntervalSince1970: 1_793_748_600) // 2026-11-03 18:30 America/New_York
        }
    }

    /// Where the rider stands in the fixtures: the south-east corner of Union Square, by the 4, 5, and 6.
    static let unionSquare = Coordinate(latitude: 40.7343, longitude: -73.9895)

    /// The bus routes at the stops around ``unionSquare``, as Nearby finds them, for line status.
    static let unionSquareBuses: [LineStatusLine] = [
        ("M14A+", "M14A-SBS", "6CBE45"),
        ("M14D+", "M14D-SBS", "6CBE45"),
        ("M1", "M1", "0039A6"),
        ("M2", "M2", "0039A6"),
    ].map { id, name, color in
        LineStatusLine(
            id: id,
            bullet: LineBullet(
                text: name,
                shape: .label,
                color: RGBColor(hex: color),
                textColor: RGBColor(hex: "FFFFFF")
            ),
            name: nil
        )
    }

    /// How old the server's realtime data is at ``referenceDate``.
    var realtimeDataAge: TimeInterval {
        self == .nycEveningStale ? 180 : 20
    }

    /// Whether trains run in this set; the bus-only sets have none, so buses show alone.
    var hasTrains: Bool {
        ![.nycEveningBuses, .nycEveningBusesStale].contains(self)
    }

    /// How old Bus Time's feed is at ``referenceDate``.
    var busDataAge: TimeInterval {
        self == .nycEveningBusesStale ? 180 : 20
    }
}
