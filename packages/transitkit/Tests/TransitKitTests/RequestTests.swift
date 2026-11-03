import Foundation
import Testing
@testable import TransitKit

struct RequestTests {
    @Test func planQueryAndUserAgent() async throws {
        let transport = try FixtureTransport(fixture: "plan-union-square-to-williamsburg")
        let client = try TransitClient(
            baseURL: #require(URL(string: "https://motis.example")),
            appVersion: "1.2",
            transport: transport
        )
        let arrival = Date(timeIntervalSince1970: 1_793_800_000) // 2026-11-04T13:46:40Z
        _ = try await client.plan(PlanRequest(
            from: .coordinate(Coordinate(latitude: 40.7359, longitude: -73.9906)),
            to: .stop(id: "us-ny-MTA-NYCSubway_M16"),
            time: .arriveBy(arrival),
            transitModes: [.subway, .bus],
            numberOfItineraries: 3,
            pageCursor: "LATER|1793800200"
        ))

        let request = try #require(transport.requests.first)
        #expect(request.method == .get)
        #expect(request.path?.hasPrefix("/api/v6/plan?") == true)
        #expect(request.headerFields[.userAgent] == "Express/1.2 (https://github.com/charleslpan/express)")
        let query = request.queryItems
        #expect(query["fromPlace"] == "40.7359,-73.9906")
        #expect(query["toPlace"] == "us-ny-MTA-NYCSubway_M16")
        #expect(query["time"] == "2026-11-04T13:46:40Z")
        #expect(query["arriveBy"] == "true")
        #expect(query["transitModes"] == "SUBWAY,BUS")
        #expect(query["numItineraries"] == "3")
        #expect(query["pageCursor"] == "LATER|1793800200")
    }

    @Test func departNowSendsOnlyThePlaces() async throws {
        let transport = try FixtureTransport(fixture: "plan-union-square-to-williamsburg")
        _ = try await TransitClient(transport: transport).plan(PlanRequest(from: .stop(id: "a"), to: .stop(id: "b")))
        let request = try #require(transport.requests.first)
        #expect(request.queryItems == ["fromPlace": "a", "toPlace": "b"])
        #expect(request.headerFields[.userAgent] == "Express/\(TransitKit.version) (\(TransitKit.contactURL))")
    }

    @Test func pageKeepsTheRequest() {
        let request = PlanRequest(from: .stop(id: "a"), to: .stop(id: "b"), time: .departAt(.distantFuture))
        let next = request.page("LATER|1")
        #expect(next.pageCursor == "LATER|1")
        #expect(next.time == request.time)
    }
}
