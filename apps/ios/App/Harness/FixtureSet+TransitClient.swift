import Foundation
import TransitKit

extension FixtureSet {
    /// A client that answers from this set and never touches the network, for the screenshot harness and previews.
    ///
    /// It serves trips around Midtown and Union Square for live trains (`Fixtures/map-trips-midtown.json`, recorded
    /// from our server and shifted to the reference date) and `/metrics` with the subway feed
    /// ``FixtureSet/realtimeDataAge`` old, in every set. Nearby's requests follow the set's network: the stops around
    /// Union Square (`Fixtures/nearby-stops.json`) and each stop's departures (`Fixtures/nearby-stoptimes-<stop>.json`,
    /// by the stop id after its feed's `_`; none for a stop without a file). So do the trip view's: a trip by its id
    /// (`Fixtures/trip-<tripId>.json`, such as the uptown 6 Nearby lists, `fixture-6-0-4`).
    var transitClient: TransitClient {
        let fixtures = self
        return TransitClient(transport: StubTransport { request in
            switch request.path {
            case "/api/v6/map/trips":
                return try Self.fixture("map-trips-midtown")
            case "/metrics":
                return Self.metrics(fixtures)
            default:
                break
            }
            switch fixtures {
            case .offline:
                throw URLError(.notConnectedToInternet)
            case .slowNetwork:
                try await Task.sleep(for: .seconds(24 * 60 * 60))
                throw CancellationError()
            case .nycEvening, .nycEveningStale, .nycNoService, .noKey:
                return try Self.response(to: request, fixtures: fixtures)
            }
        })
    }

    private static func response(to request: StubTransport.Request, fixtures: FixtureSet) throws -> Data {
        switch request.path {
        case "/api/v6/map/stops":
            return try fixture("nearby-stops")
        case "/api/v6/stoptimes":
            let stopId = request.query["stopId"] ?? ""
            let feedStopId = stopId.split(separator: "_").last.map(String.init) ?? stopId
            if fixtures != .nycNoService, let data = try? fixture("nearby-stoptimes-\(feedStopId)") {
                return data
            }
            return noDepartures
        case "/api/v6/trip":
            return try fixture("trip-\(request.query["tripId"] ?? "")")
        default:
            throw URLError(.resourceUnavailable)
        }
    }

    /// The server's `/metrics`, with the subway feed's timestamp as old as the set's data is.
    private static func metrics(_ fixtures: FixtureSet) -> Data {
        let timestamp = Int(fixtures.referenceDate.timeIntervalSince1970 - fixtures.realtimeDataAge)
        return Data("nigiri_gtfsrt_feed_timestamp_seconds{tag=\"us-ny-MTA-NYCSubway\"} \(timestamp)\n".utf8)
    }

    /// A `stoptimes` answer with nothing due.
    private static let noDepartures = Data("""
    {"stopTimes": [], "place": {"name": "", "lat": 0, "lon": 0}, "previousPageCursor": "", "nextPageCursor": ""}
    """.utf8)

    private static func fixture(_ name: String) throws -> Data {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
            throw URLError(.fileDoesNotExist)
        }
        return try Data(contentsOf: url)
    }
}
