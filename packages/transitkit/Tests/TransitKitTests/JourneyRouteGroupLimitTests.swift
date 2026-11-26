import Testing
@testable import TransitKit

/// The options list shows at most five route groups.
struct JourneyRouteGroupLimitTests {
    @Test func onlyTheTopFiveRoutesShowWithAllTheirDepartures() throws {
        let planned = try JourneyRouteGroupTests.transfer()
        // Seven routes, ranked in order; the first also has two later trips.
        var itineraries = (0 ..< 7).map { index in
            JourneyRouteGroupTests.later(planned, by: index + 1) { $0.routeId = "route-\(index)" }
        }
        itineraries.insert(contentsOf: [JourneyRouteGroupTests.later(itineraries[0], by: 10), JourneyRouteGroupTests.later(itineraries[0], by: 20)], at: 1)
        let options = itineraries.map(JourneyOption.init)
        let groups = JourneyOptions.groups(of: options)

        #expect(groups.count == 5)
        #expect(groups.map(\.primary.id) == [0, 3, 4, 5, 6].map { itineraries[$0].id })
        #expect(groups[0].options.count == 3)
        #expect(JourneyOptions.groups(of: options, limit: .max).count == 7)
    }
}
