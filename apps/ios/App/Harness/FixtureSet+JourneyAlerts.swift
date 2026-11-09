import Foundation

extension FixtureSet {
    /// An itinerary answer (a plan, a trip, or the harness's own journeys) with the alerts
    /// `Fixtures/journey-alerts.json` lists, attached as MOTIS attaches them: a line's on each leg riding that trip
    /// (`lines`, by trip id, as `leg.alerts`), and a stop's on that trip's stop of that name (`stops`, by
    /// `<tripId>|<stop name>`, as `place.alerts`).
    ///
    /// They make `nyc-alerts`' journeys: the 4 delayed (amber), the 42 St Shuttle suspended (red), the L skipping
    /// 14 St-Union Sq where the rider boards it, and the 6 with night work two weeks away and delays that ended before
    /// the ride, neither of which applies. `nyc-alerts-mixed` adds `Fixtures/journey-alerts-mixed.json`'s after them:
    /// the Q running local (neutral) on the Q and shuttle journey.
    static func withJourneyAlerts(_ data: Data, fixtures: FixtureSet = .nycAlerts) throws -> Data {
        var lines: [String: [Any]] = [:]
        var stops: [String: [Any]] = [:]
        let names = fixtures == .nycAlertsMixed ? ["journey-alerts", "journey-alerts-mixed"] : ["journey-alerts"]
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
                throw URLError(.fileDoesNotExist)
            }
            let alerts = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: [String: [Any]]]
            lines.merge(alerts?["lines"] ?? [:]) { $0 + $1 }
            stops.merge(alerts?["stops"] ?? [:]) { $0 + $1 }
        }
        guard var answer = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return data }

        func place(_ value: Any, trip: String) -> Any {
            guard var place = value as? [String: Any], let name = place["name"] as? String,
                  let attached = stops["\(trip)|\(name)"]
            else { return value }
            place["alerts"] = attached
            return place
        }
        func leg(_ value: [String: Any]) -> [String: Any] {
            guard let trip = value["tripId"] as? String else { return value }
            var leg = value
            if let attached = lines[trip] {
                leg["alerts"] = attached
            }
            for end in ["from", "to"] {
                if let value = leg[end] {
                    leg[end] = place(value, trip: trip)
                }
            }
            if let between = leg["intermediateStops"] as? [Any] {
                leg["intermediateStops"] = between.map { place($0, trip: trip) }
            }
            return leg
        }
        func itinerary(_ value: [String: Any]) -> [String: Any] {
            var itinerary = value
            if let legs = value["legs"] as? [[String: Any]] {
                itinerary["legs"] = legs.map(leg)
            }
            return itinerary
        }

        if let itineraries = answer["itineraries"] as? [[String: Any]] {
            answer["itineraries"] = itineraries.map(itinerary)
        } else {
            answer = itinerary(answer)
        }
        return try JSONSerialization.data(withJSONObject: answer)
    }
}
