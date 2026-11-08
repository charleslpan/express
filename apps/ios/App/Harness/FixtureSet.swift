import Foundation
import TransitKit

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
    /// The same evening, with the subway's live data three minutes old, so screens say it may not be real time.
    case nycEveningStale = "nyc-evening-stale"
    /// The same evening's buses with no trains running, so the map shows buses alone.
    case nycEveningBuses = "nyc-evening-buses"
    /// Buses alone, with Bus Time's feed three minutes old, so the map says bus positions may not be real time.
    case nycEveningBusesStale = "nyc-evening-buses-stale"

    /// The moment the fixtures describe, which stands in for "now" so times on screen don't drift between runs.
    var referenceDate: Date {
        switch self {
        case .nycEvening, .nycEveningStale, .nycEveningBuses, .nycEveningBusesStale, .slowNetwork, .offline, .noKey:
            Date(timeIntervalSince1970: 1_793_748_600) // 2026-11-03 18:30 America/New_York
        }
    }

    /// A ``TransitClient`` that answers from this set's recorded responses (`Harness/Fixtures/`), never the network.
    var transitClient: TransitClient {
        TransitClient(cannedResponses: [
            // Trips around Midtown and Union Square, recorded from our server and shifted to the reference date.
            "trips": hasTrains ? Self.resource("map-trips-midtown") : Data("[]".utf8),
            "metrics": Data(metrics.utf8),
            // Buses around Midtown and Union Square from `/api/vehicles/bus`, and their routes' labels and colours.
            "vehiclesBus": busPositions,
            "routes": Self.resource("map-routes-midtown"),
        ].compactMapValues(\.self))
    }

    /// The server's `/metrics`, with the subway feed's timestamp as old as this set's data is.
    private var metrics: String {
        let age: TimeInterval = self == .nycEveningStale ? 180 : 20
        let timestamp = Int(referenceDate.timeIntervalSince1970 - age)
        return "nigiri_gtfsrt_feed_timestamp_seconds{tag=\"us-ny-MTA-NYCSubway\"} \(timestamp)\n"
    }

    /// Whether trains run in this set; the bus-only sets have none, so buses show alone.
    private var hasTrains: Bool {
        ![.nycEveningBuses, .nycEveningBusesStale].contains(self)
    }

    /// `/api/vehicles/bus`'s answer, its feed as old as this set's bus data is: 20 seconds, or 3 minutes when stale.
    ///
    /// The fixture's positions are on real routes in Midtown; the colours in `map-routes-midtown.json` are the feed's
    /// for the 14 St SBS routes and illustrative for the rest.
    private var busPositions: Data? {
        guard let data = Self.resource("vehicles-bus-midtown") else { return nil }
        guard self == .nycEveningBusesStale,
              var response = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return data }
        response["updatedAt"] = Int(referenceDate.timeIntervalSince1970) - 180
        return try? JSONSerialization.data(withJSONObject: response)
    }

    private static func resource(_ name: String) -> Data? {
        Bundle.main.url(forResource: name, withExtension: "json").flatMap { try? Data(contentsOf: $0) }
    }
}
