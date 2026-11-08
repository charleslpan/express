import Foundation
import TransitKit

extension FixtureSet {
    /// A client that answers from this set and never touches the network, for the screenshot harness and previews.
    ///
    /// It serves the stops around Union Square (`Fixtures/nearby-stops.json`), each stop's departures
    /// (`Fixtures/nearby-stoptimes-<stop>.json`, by the stop id after its feed's `_`; none for a stop without a
    /// file), and `/metrics` with the subway feed ``FixtureSet/realtimeDataAge`` old.
    var transitClient: TransitClient {
        let fixtures = self
        return TransitClient(transport: StubTransport { request in
            switch fixtures {
            case .offline:
                throw URLError(.notConnectedToInternet)
            case .slowNetwork:
                try await Task.sleep(for: .seconds(24 * 60 * 60))
                throw CancellationError()
            case .nycEvening, .nycEveningStale, .nycNoService, .noKey:
                try Self.response(to: request, fixtures: fixtures)
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
        case "/metrics":
            let timestamp = Int(fixtures.referenceDate.timeIntervalSince1970 - fixtures.realtimeDataAge)
            return Data("nigiri_gtfsrt_feed_timestamp_seconds{tag=\"us-ny-MTA-NYCSubway\"} \(timestamp)\n".utf8)
        default:
            throw URLError(.resourceUnavailable)
        }
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
