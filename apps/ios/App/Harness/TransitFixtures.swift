import Foundation
import TransitKit

extension TransitClient {
    /// A client on a fixture set's recorded data, which never touches the network.
    ///
    /// Every set plans from Union Square to Grand Central Terminal at its reference time (`Fixtures/
    /// plan-nyc-evening.json`: the 4, the 6 running late, the Q and the shuttle, the M101, and a walk), with realtime
    /// feeds 20 seconds old; except `no-journeys`, which finds none, `stale-data`, whose feeds are five minutes old,
    /// `slow-network`, which never answers, and `offline`, which fails as offline.
    static func fixtures(_ fixtures: FixtureSet) -> TransitClient {
        let plan = Bundle.main.url(forResource: "plan-nyc-evening", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) } ?? Data()
        let feedAge: TimeInterval = fixtures == .staleData ? 300 : 20
        let feedTimestamp = Int(fixtures.referenceDate.timeIntervalSince1970 - feedAge)
        let metrics = "nigiri_gtfsrt_feed_timestamp_seconds{tag=\"us-ny-MTA-NYCSubway\"} \(feedTimestamp)\n"
        return TransitClient(transport: CannedTransport { operation in
            switch (fixtures, operation) {
            case (.slowNetwork, _): .never
            case (.offline, _): .offline
            case (.noJourneys, "plan"): .json(emptyPlan)
            case (_, "plan"): .json(plan)
            case (_, "metrics"): .text(metrics)
            default: .status(404)
            }
        })
    }

    /// A plan with no itineraries, which ``TransitClient/plan(_:)`` reports as no route.
    private static let emptyPlan = Data("""
    {
      "requestParameters": {}, "debugOutput": {},
      "from": {"name": "START", "lat": 40.7359, "lon": -73.9906},
      "to": {"name": "END", "lat": 40.7527, "lon": -73.9772},
      "direct": [], "itineraries": [], "previousPageCursor": "", "nextPageCursor": ""
    }
    """.utf8)
}
