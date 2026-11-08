import Foundation
import TransitKit

/// A named, deterministic set of data for the app to show instead of live data, selected with `-fixtures <name>`.
/// Add a case for a new scenario; fixture-backed data clients switch over it to decide what to return.
enum FixtureSet: String, CaseIterable, Sendable {
    /// Weekday evening rush in Manhattan.
    case nycEvening = "nyc-evening"
    /// The same evening, with the subway's live data three minutes old, so screens say it may not be real time.
    case nycEveningStale = "nyc-evening-stale"

    /// The moment the fixtures describe, which stands in for "now" so times on screen don't drift between runs.
    var referenceDate: Date {
        switch self {
        // 2026-11-03 18:30 America/New_York
        case .nycEvening, .nycEveningStale: Date(timeIntervalSince1970: 1_793_748_600)
        }
    }

    /// A ``TransitClient`` that answers from this set's recorded responses (`Harness/Fixtures/`), never the network.
    var transitClient: TransitClient {
        TransitClient(cannedResponses: [
            // Trips around Midtown and Union Square, recorded from our server and shifted to the reference date.
            "trips": Self.resource("map-trips-midtown"),
            "metrics": Data(metrics.utf8),
        ].compactMapValues(\.self))
    }

    /// The server's `/metrics`, with the subway feed's timestamp as old as this set's data is.
    private var metrics: String {
        let age: TimeInterval = switch self {
        case .nycEvening: 20
        case .nycEveningStale: 180
        }
        let timestamp = Int(referenceDate.timeIntervalSince1970 - age)
        return "nigiri_gtfsrt_feed_timestamp_seconds{tag=\"us-ny-MTA-NYCSubway\"} \(timestamp)\n"
    }

    private static func resource(_ name: String) -> Data? {
        Bundle.main.url(forResource: name, withExtension: "json").flatMap { try? Data(contentsOf: $0) }
    }
}
