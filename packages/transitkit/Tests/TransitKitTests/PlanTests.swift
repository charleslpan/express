import Foundation
import Testing
@testable import TransitKit

struct PlanTests {
    static let unionSquare = Coordinate(latitude: 40.7359, longitude: -73.9906)
    static let marcyAvenue = Coordinate(latitude: 40.7083, longitude: -73.9578)

    @Test func subwayTripWithTransfer() async throws {
        let transport = try FixtureTransport(fixture: "plan-union-square-to-williamsburg")
        let client = TransitClient(transport: transport)
        let response = try await client.plan(PlanRequest(
            from: .coordinate(Self.unionSquare),
            to: .coordinate(Self.marcyAvenue)
        ))

        let itinerary = try #require(response.itineraries.first)
        #expect(itinerary.transfers == 1)
        #expect(itinerary.duration == 1320)
        #expect(itinerary.formattedDuration == "22 min")
        #expect(itinerary.legs.map(\.mode) == [.walk, .subway, .walk, .subway, .walk])
        #expect(itinerary.transitLegs.compactMap(\.lineName) == ["W", "M"])

        let ride = itinerary.legs[1]
        #expect(ride.from.name == "14 St-Union Sq")
        #expect(ride.from.stopId == "us-ny-MTA-NYCSubway_R20S")
        #expect(ride.from.parentId == "us-ny-MTA-NYCSubway_R20")
        #expect(ride.routeRGBColor == RGBColor(hex: "f6bc26"))
        #expect(!ride.isRealtime)
        #expect(ride.departureDelayMinutes == nil)
        #expect(response.laterPageCursor?.hasPrefix("LATER|") == true)
        #expect(response.earlierPageCursor?.hasPrefix("EARLIER|") == true)
        #expect(Set(itinerary.legs.map(\.id)).count == itinerary.legs.count)
    }

    @Test func busPlusSubwayTripWithRealtime() async throws {
        let client = try TransitClient(transport: FixtureTransport(fixture: "plan-red-hook-to-times-square"))
        let request = PlanRequest(
            from: .coordinate(Coordinate(latitude: 40.6757, longitude: -74.0086)),
            to: .coordinate(Coordinate(latitude: 40.7580, longitude: -73.9855))
        )
        let itinerary = try #require(await client.plan(request).itineraries.first)
        #expect(itinerary.legs.map(\.mode) == [.walk, .bus, .walk, .subway, .walk])

        let bus = itinerary.legs[1]
        #expect(bus.lineName == "B57")
        #expect(bus.isRealtime)
        #expect(bus.from.isRealtime)
        #expect(bus.from.departureTimestampReason == .predicted)
        // Predicted 20:31, scheduled 20:33: two minutes early.
        #expect(bus.departureDelayMinutes == -2)
        #expect(bus.from.departureDelayMinutes == -2)
        #expect(itinerary.isRealtime)

        let subway = itinerary.legs[3]
        #expect(subway.lineName == "A")
        #expect(!subway.isRealtime)
        #expect(subway.from.departureTimestampReason == .noRtData)
        #expect(subway.from.departureDelayMinutes == nil)
        #expect(!subway.from.isRealtime)
    }

    @Test func statenIslandRailwayTrip() async throws {
        let client = try TransitClient(transport: FixtureTransport(fixture: "plan-great-kills-to-st-george"))
        let request = PlanRequest(
            from: .coordinate(Coordinate(latitude: 40.5512, longitude: -74.1515)),
            to: .coordinate(Coordinate(latitude: 40.6437, longitude: -74.0736))
        )
        let itinerary = try #require(await client.plan(request).itineraries.first)
        #expect(itinerary.transfers == 0)
        let sir = try #require(itinerary.transitLegs.first)
        #expect(sir.mode == .regionalRail)
        #expect(sir.lineName == "SIR")
        #expect(sir.from.name == "Great Kills")
        #expect(sir.to.name == "St George")
        #expect(sir.intermediateStops?.count == 11)
        #expect(sir.formattedDuration == "25 min")
    }

    @Test func noItinerariesIsNoRoute() async throws {
        let body = Data("""
        {
          "requestParameters": {}, "debugOutput": {},
          "from": {"name": "START", "lat": 40.7, "lon": -74.0, "level": 0},
          "to": {"name": "END", "lat": 0, "lon": 0, "level": 0},
          "direct": [], "itineraries": [], "previousPageCursor": "", "nextPageCursor": ""
        }
        """.utf8)
        let client = TransitClient(transport: FixtureTransport(body: body))
        await #expect(throws: TransitError.noRoute) {
            try await client.plan(PlanRequest(from: .stop(id: "a"), to: .stop(id: "b")))
        }
        // A page past the last one is just empty.
        let page = try await client.plan(PlanRequest(from: .stop(id: "a"), to: .stop(id: "b"), pageCursor: "LATER|1"))
        #expect(page.itineraries.isEmpty)
        #expect(page.laterPageCursor == nil)
    }

    @Test func refreshItinerary() async throws {
        let itinerary = try FixtureTransport.firstItinerary("plan-union-square-to-williamsburg")
        let transport = try FixtureTransport(fixture: "refresh-union-square-to-williamsburg")
        let refreshed = try await TransitClient(transport: transport).refresh(itinerary)
        #expect(refreshed.legs.map(\.mode) == itinerary.legs.map(\.mode))
        #expect(refreshed.id == itinerary.id)

        let request = try #require(transport.requests.first)
        #expect(request.path?.hasPrefix("/api/v6/refresh-itinerary?") == true)
        #expect(request.queryItems["itineraryId"] == itinerary.id)
    }
}
