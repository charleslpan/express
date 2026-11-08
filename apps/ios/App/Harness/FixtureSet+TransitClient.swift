import Foundation
import TransitKit

extension FixtureSet {
    /// A client that answers from this set and never touches the network, for the screenshot harness and previews.
    ///
    /// It serves trips around Midtown and Union Square for live trains (`Fixtures/map-trips-midtown.json`, recorded
    /// from our server and shifted to the reference date) and `/metrics` with the subway feed
    /// ``FixtureSet/realtimeDataAge`` old, in every set. Nearby's requests follow the set's network: the stops around
    /// Union Square (`Fixtures/nearby-stops.json`) and each stop's departures (`Fixtures/nearby-stoptimes-<stop>.json`,
    /// by the stop id after its feed's `_`; none for a stop without a file). Live buses get Midtown's buses from
    /// `/api/vehicles/bus` (`Fixtures/vehicles-bus-midtown.json`, its feed ``FixtureSet/busDataAge`` old) and their
    /// routes' labels and colours (`Fixtures/map-routes-midtown.json`: the feed's for the 14 St SBS routes,
    /// illustrative for the rest). The bus-only sets run no trains. Journeys plan from Union Square to Grand Central
    /// Terminal (`Fixtures/plan-nyc-evening.json`: the 4, the 6 running late, the Q and the shuttle, the M101, and a
    /// walk), except in `no-journeys`, which finds none.
    var transitClient: TransitClient {
        let fixtures = self
        return TransitClient(transport: StubTransport { request in
            switch request.path {
            case "/api/v6/map/trips":
                return fixtures.hasTrains ? try Self.fixture("map-trips-midtown") : Data("[]".utf8)
            case "/api/vehicles/bus":
                return try Self.busPositions(fixtures)
            case "/api/experimental/map/routes":
                return try Self.fixture("map-routes-midtown")
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
            case .nycEvening, .nycEveningStale, .nycNoService, .nycEveningBuses, .nycEveningBusesStale, .noKey,
                 .noJourneys:
                return try Self.response(to: request, fixtures: fixtures)
            }
        })
    }

    private static func response(to request: StubTransport.Request, fixtures: FixtureSet) throws -> Data {
        switch request.path {
        case "/api/v6/map/stops":
            return try fixture("nearby-stops")
        case "/api/v6/plan":
            return fixtures == .noJourneys ? emptyPlan : try fixture("plan-nyc-evening")
        case "/api/v6/stoptimes":
            let stopId = request.query["stopId"] ?? ""
            let feedStopId = stopId.split(separator: "_").last.map(String.init) ?? stopId
            if fixtures != .nycNoService, let data = try? fixture("nearby-stoptimes-\(feedStopId)") {
                return data
            }
            return noDepartures
        default:
            throw URLError(.resourceUnavailable)
        }
    }

    /// The server's `/metrics`, with the subway feed's timestamp as old as the set's data is.
    private static func metrics(_ fixtures: FixtureSet) -> Data {
        let timestamp = Int(fixtures.referenceDate.timeIntervalSince1970 - fixtures.realtimeDataAge)
        return Data("nigiri_gtfsrt_feed_timestamp_seconds{tag=\"us-ny-MTA-NYCSubway\"} \(timestamp)\n".utf8)
    }

    /// A `plan` answer with no itineraries, which ``TransitClient/plan(_:)`` reports as no route.
    private static let emptyPlan = Data("""
    {
      "requestParameters": {}, "debugOutput": {},
      "from": {"name": "START", "lat": 40.7359, "lon": -73.9906},
      "to": {"name": "END", "lat": 40.7527, "lon": -73.9772},
      "direct": [], "itineraries": [], "previousPageCursor": "", "nextPageCursor": ""
    }
    """.utf8)

    /// `/api/vehicles/bus`'s answer, with Bus Time's feed as old as the set's bus data is.
    private static func busPositions(_ fixtures: FixtureSet) throws -> Data {
        let data = try fixture("vehicles-bus-midtown")
        guard var response = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return data }
        response["updatedAt"] = Int(fixtures.referenceDate.timeIntervalSince1970 - fixtures.busDataAge)
        return try JSONSerialization.data(withJSONObject: response)
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
