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
    /// illustrative for the rest). The bus-only sets run no trains. The trip view's
    /// requests follow the set's network too: a trip by its id (`Fixtures/trip-<tripId>.json`, such as the uptown 6
    /// Nearby lists, `fixture-6-0-4`), and the trips the journeys ride (`fixture-trip-6` and the rest, which journey
    /// detail refreshes from; `nyc-evening-cancelled` cancels the 6, from `trip-fixture-trip-6-cancelled.json`).
    /// Journeys plan from Union Square to Grand Central Terminal (`Fixtures/plan-nyc-evening.json`: the 4, the 6
    /// running late, the Q and the shuttle, the M101, and a walk), except in `no-journeys`, which finds none.
    /// Line status (`/api/alerts`) answers every requested line with no alerts, but in `nyc-alerts`, which answers from
    /// `Fixtures/line-status-nyc-alerts.json` (the MTA's alerts recorded that evening, with the set's own) and adds
    /// `Fixtures/nearby-alerts.json` to the departures and `Fixtures/journey-alerts.json` to the journeys' legs and
    /// trips.
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
                 .noJourneys, .nycEveningCancelled, .nycAlerts:
                return try Self.response(to: request, fixtures: fixtures)
            }
        })
    }

    private static func response(to request: StubTransport.Request, fixtures: FixtureSet) throws -> Data {
        switch request.path {
        case "/api/v6/map/stops":
            return try fixture("nearby-stops")
        case "/api/v6/plan":
            return fixtures == .noJourneys ? emptyPlan : try itineraries("plan-nyc-evening", fixtures: fixtures)
        case "/api/v6/stoptimes":
            let stopId = request.query["stopId"] ?? ""
            let feedStopId = stopId.split(separator: "_").last.map(String.init) ?? stopId
            if fixtures != .nycNoService, let data = try? fixture("nearby-stoptimes-\(feedStopId)") {
                if fixtures == .nycAlerts {
                    return try withAlerts(data)
                }
                return data
            }
            return noDepartures
        case "/api/v6/trip":
            let tripId = request.query["tripId"] ?? ""
            if fixtures == .nycEveningCancelled, let cancelled = try? fixture("trip-\(tripId)-cancelled") {
                return cancelled
            }
            return try itineraries("trip-\(tripId)", fixtures: fixtures)
        case "/api/alerts":
            return try lineStatus(lines: request.query["lines"] ?? "", fixtures: fixtures)
        default:
            throw URLError(.resourceUnavailable)
        }
    }

    /// A plan or trip fixture, with the set's journey alerts in `nyc-alerts` (``withJourneyAlerts(_:)``).
    private static func itineraries(_ name: String, fixtures: FixtureSet) throws -> Data {
        let data = try fixture(name)
        return fixtures == .nycAlerts ? try withJourneyAlerts(data) : data
    }

    /// The server's `/metrics`, with the subway feed's timestamp as old as the set's data is.
    private static func metrics(_ fixtures: FixtureSet) -> Data {
        let timestamp = Int(fixtures.referenceDate.timeIntervalSince1970 - fixtures.realtimeDataAge)
        return Data("nigiri_gtfsrt_feed_timestamp_seconds{tag=\"us-ny-MTA-NYCSubway\"} \(timestamp)\n".utf8)
    }

    /// A `stoptimes` answer with each departure given the alerts `Fixtures/nearby-alerts.json` lists for its route, or
    /// for its route and direction (`<routeId>|<directionId>`), as MOTIS attaches them (`place.alerts`).
    private static func withAlerts(_ data: Data) throws -> Data {
        let alerts = try JSONSerialization.jsonObject(with: fixture("nearby-alerts")) as? [String: [Any]] ?? [:]
        guard var answer = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stopTimes = answer["stopTimes"] as? [[String: Any]]
        else { return data }
        answer["stopTimes"] = stopTimes.map { stopTime in
            let route = stopTime["routeId"] as? String ?? ""
            let direction = stopTime["directionId"] as? String ?? ""
            let attached = (alerts[route] ?? []) + (alerts["\(route)|\(direction)"] ?? [])
            guard !attached.isEmpty, var place = stopTime["place"] as? [String: Any] else { return stopTime }
            place["alerts"] = attached
            var stopTime = stopTime
            stopTime["place"] = place
            return stopTime
        }
        return try JSONSerialization.data(withJSONObject: answer)
    }

    /// The line status endpoint's answer for a comma-separated `lines`: each line's alerts in `nyc-alerts`, none in
    /// every other set.
    private static func lineStatus(lines: String, fixtures: FixtureSet) throws -> Data {
        var recorded: [String: Any] = [:]
        var updatedAt: Any = ["subway": NSNull(), "bus": NSNull()]
        if fixtures == .nycAlerts,
           let answer = try JSONSerialization.jsonObject(with: fixture("line-status-nyc-alerts")) as? [String: Any]
        {
            recorded = answer["lines"] as? [String: Any] ?? [:]
            updatedAt = answer["updatedAt"] ?? updatedAt
        }
        let requested = lines.split(separator: ",").map(String.init)
        let lines = requested.map { ($0, recorded[$0] ?? [Any]()) }
        let answer: [String: Any] = [
            "updatedAt": updatedAt,
            "lines": Dictionary(lines, uniquingKeysWith: { first, _ in first }),
        ]
        return try JSONSerialization.data(withJSONObject: answer)
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

    /// A journey the screenshot harness opens in detail, by its id: one the plan offers
    /// (`Fixtures/plan-nyc-evening.json`), or one only the harness opens (`Fixtures/journeys-detail.json`: the L and
    /// the M101 with a transfer at 3 Av, `fixture-l-m101`). In `nyc-alerts` it carries the set's journey alerts
    /// (``withJourneyAlerts(_:)``), as the plan does.
    static func journey(id: String, fixtures: FixtureSet = .nycEvening) -> Itinerary? {
        struct Journeys: Decodable {
            var itineraries: [Itinerary]
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for name in ["plan-nyc-evening", "journeys-detail"] {
            guard var data = try? fixture(name) else { continue }
            if fixtures == .nycAlerts, let withAlerts = try? withJourneyAlerts(data) {
                data = withAlerts
            }
            guard let journeys = try? decoder.decode(Journeys.self, from: data) else { continue }
            if let journey = journeys.itineraries.first(where: { $0.id == id }) {
                return journey
            }
        }
        return nil
    }

    private static func fixture(_ name: String) throws -> Data {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
            throw URLError(.fileDoesNotExist)
        }
        return try Data(contentsOf: url)
    }
}
