import Foundation
import Testing
@testable import TransitKit

struct StopTests {
    static func date(_ string: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: string))
    }

    @Test func departuresAtUnionSquare() async throws {
        let transport = try FixtureTransport(fixture: "stoptimes-union-square")
        let client = TransitClient(transport: transport)
        let response = try await client.departures(DeparturesRequest(stopId: "us-ny-MTA-NYCSubway_635", count: 8))

        #expect(response.place.name == "14 St-Union Sq")
        // One parent's id lists the whole complex: platforms under 635, L03, and R20.
        #expect(Set(response.stopTimes.compactMap(\.place.parentId)) == [
            "us-ny-MTA-NYCSubway_635", "us-ny-MTA-NYCSubway_L03", "us-ny-MTA-NYCSubway_R20",
        ])
        #expect(response.stopTimes.compactMap(\.lineName) == ["L", "N", "6X", "L", "5", "6", "Q", "6", "R"])
        #expect(Set(response.stopTimes.map(\.id)).count == response.stopTimes.count)
        #expect(response.laterPageCursor?.hasPrefix("LATER|") == true)
        #expect(response.earlierPageCursor?.hasPrefix("EARLIER|") == true)

        let express = response.stopTimes[2]
        #expect(express.headsign == "Pelham Bay Park")
        #expect(express.mode == .subway)
        #expect(express.isRealtime)
        #expect(!express.isCancelled)
        // Scheduled 21:05, predicted 21:07: two minutes late.
        #expect(try express.scheduledTime == Self.date("2026-11-03T21:05:00Z"))
        #expect(try express.time == Self.date("2026-11-03T21:07:00Z"))
        #expect(express.delayMinutes == 2)
        #expect(try express.minutesUntil(from: Self.date("2026-11-03T21:04:30Z")) == 2)
        #expect(express.routeRGBColor == RGBColor(hex: "009952"))
        #expect(express.routeTextRGBColor == RGBColor(hex: "ffffff"))

        // Predicted 21:09 against 21:10: a minute early.
        #expect(response.stopTimes[7].delayMinutes == -1)

        let scheduledOnly = response.stopTimes[3]
        #expect(!scheduledOnly.isRealtime)
        #expect(scheduledOnly.delayMinutes == nil)
        #expect(scheduledOnly.time == scheduledOnly.scheduledTime)

        let request = try #require(transport.requests.first)
        #expect(request.path?.hasPrefix("/api/v6/stoptimes?") == true)
        #expect(request.queryItems["stopId"] == "us-ny-MTA-NYCSubway_635")
        #expect(request.queryItems["n"] == "8")
        #expect(request.queryItems["arriveBy"] == nil)
    }

    @Test func departuresAtABusStop() async throws {
        let client = try TransitClient(transport: FixtureTransport(fixture: "stoptimes-e-14-st-irving-pl"))
        let response = try await client.departures(DeparturesRequest(stopId: "us-ny-MTA-BusManhattan_403556"))
        #expect(response.place.name == "E 14 ST/IRVING PL")
        #expect(response.stopTimes.allSatisfy { $0.mode == .bus })
        #expect(Set(response.stopTimes.compactMap(\.lineName)) == ["M14A-SBS", "M14D-SBS"])

        let early = response.stopTimes[1]
        #expect(early.isRealtime)
        #expect(early.delayMinutes == -3)
    }

    @Test func cancelledDeparture() throws {
        var departure = try Self.firstDeparture()
        #expect(!departure.isCancelled)
        departure.tripCancelled = true
        #expect(departure.isCancelled)
        departure.tripCancelled = false
        departure.cancelled = true
        #expect(departure.isCancelled)
    }

    @Test func departuresRequestQuery() {
        let time = Date(timeIntervalSince1970: 1_793_739_600)
        var request = DeparturesRequest(
            stopId: "us-ny-MTA-NYCSubway_635",
            kind: .arrivals,
            time: time,
            window: 1800,
            transitModes: [.subway]
        )
        var query = request.query
        #expect(query.stopId == "us-ny-MTA-NYCSubway_635")
        #expect(query.time == time)
        #expect(query.arriveBy == true)
        #expect(query.direction == .later)
        #expect(query.window == 1800)
        #expect(query.n == nil)
        #expect(query.mode == [.subway])

        request = request.page("LATER|1793740200")
        query = request.query
        #expect(query.pageCursor == "LATER|1793740200")
        #expect(DeparturesRequest(stopId: "a").query.arriveBy == nil)
    }

    @Test func departuresErrors() async {
        let body = Data(#"{"error":"stop not found"}"#.utf8)
        let client = TransitClient(transport: FixtureTransport(status: .notFound, body: body))
        await #expect(throws: TransitError.server(statusCode: 404, message: "stop not found")) {
            try await client.departures(DeparturesRequest(stopId: "nope"))
        }
        let offline = TransitClient(transport: FixtureTransport(error: URLError(.notConnectedToInternet)))
        await #expect(throws: TransitError.offline) {
            try await offline.stops(
                southWest: Coordinate(latitude: 40.733, longitude: -73.9935),
                northEast: Coordinate(latitude: 40.738, longitude: -73.9875)
            )
        }
    }

    @Test func stopsAroundUnionSquare() async throws {
        let transport = try FixtureTransport(fixture: "map-stops-union-square")
        let stops = try await TransitClient(transport: transport).stops(
            southWest: Coordinate(latitude: 40.733, longitude: -73.9935),
            northEast: Coordinate(latitude: 40.738, longitude: -73.9875)
        )
        #expect(stops.count == 19)

        let request = try #require(transport.requests.first)
        #expect(request.path?.hasPrefix("/api/v6/map/stops?") == true)
        #expect(request.queryItems["min"] == "40.733,-73.9935")
        #expect(request.queryItems["max"] == "40.738,-73.9875")

        // Brooklyn's and Staten Island's feeds both carry stop 404197.
        let deduplicated = stops.deduplicated()
        #expect(deduplicated.count == 18)
        #expect(deduplicated.contains { $0.stopId == "us-ny-MTA-BusBrooklyn_404197" })
        #expect(!deduplicated.contains { $0.stopId == "us-ny-MTA-BusStatenIsland_404197" })
        // Same name, different poles: both kept.
        #expect(deduplicated.contains { $0.stopId == "us-ny-MTA-BusStatenIsland_404993" })
        #expect(deduplicated.count(where: { $0.name == "E 14 ST/IRVING PL" }) == 2)

        let stations = stops.groupedIntoStations()
        // Six platforms under three parents make one complex; each of the 12 bus stops stands alone.
        #expect(stations.count == 13)
        let unionSquare = try #require(stations.first { $0.name == "14 St-Union Sq" })
        #expect(unionSquare.isComplex)
        #expect(unionSquare.id == "us-ny-MTA-NYCSubway_635")
        #expect(unionSquare.stopIds == [
            "us-ny-MTA-NYCSubway_635", "us-ny-MTA-NYCSubway_L03", "us-ny-MTA-NYCSubway_R20",
        ])
        #expect(unionSquare.platforms.count == 6)
        #expect(unionSquare.modes == [.subway])
        #expect(unionSquare.platforms.allSatisfy { $0.stationId == $0.parentId })
        #expect(unionSquare.coordinate.distance(to: Coordinate(latitude: 40.7351, longitude: -73.9904)) < 50)

        let busStop = try #require(stations.first { $0.id == "us-ny-MTA-BusManhattan_403556" })
        #expect(!busStop.isComplex)
        #expect(busStop.stopIds == ["us-ny-MTA-BusManhattan_403556"])
        #expect(busStop.modes == [.bus])
        #expect(busStop.platforms.first?.stationId == "us-ny-MTA-BusManhattan_403556")
    }

    @Test func sameNamedStationsFarApartStaySeparate() {
        let near = Stop(name: "23 St", stopId: "x_A30N", parentId: "x_A30", lat: 40.7429, lon: -73.9928)
        let far = Stop(name: "23 St", stopId: "x_634N", parentId: "x_634", lat: 40.7398, lon: -73.9866)
        let stations = [near, far].groupedIntoStations()
        #expect(stations.count == 2)
        #expect(stations.map(\.id) == ["x_A30", "x_634"])
    }

    @Test func distance() {
        let unionSquare = Coordinate(latitude: 40.7359, longitude: -73.9906)
        let timesSquare = Coordinate(latitude: 40.7580, longitude: -73.9855)
        // About 2.5 km up Broadway.
        #expect(abs(unionSquare.distance(to: timesSquare) - 2492) < 25)
        #expect(unionSquare.distance(to: unionSquare) == 0)
    }

    @Test func tripStopsAndShape() async throws {
        let transport = try FixtureTransport(fixture: "trip-6x-pelham-bay-park")
        let tripId = "20261103_15:57_us-ny-MTA-NYCSubway_L0S2-6-1092-S01_095750_6..N02R"
        let trip = try await TransitClient(transport: transport).trip(id: tripId)

        let request = try #require(transport.requests.first)
        #expect(request.path?.hasPrefix("/api/v6/trip?") == true)
        #expect(request.queryItems["tripId"] == tripId)

        let leg = try #require(trip.transitLegs.first)
        #expect(leg.lineName == "6X")
        let stops = trip.tripStops
        #expect(stops.count == 29)
        #expect(stops.first?.name == "Brooklyn Bridge-City Hall")
        #expect(stops.last?.name == "Pelham Bay Park")
        #expect(stops.contains { $0.parentId == "us-ny-MTA-NYCSubway_635" })
        #expect(Set(stops.compactMap(\.stopId)).count == stops.count)
        #expect(trip.coordinates.count == leg.legGeometry.length)
    }

    static func firstDeparture() throws -> Departure {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try FixtureTransport.fixture("stoptimes-union-square")
        return try #require(decoder.decode(DeparturesResponse.self, from: data).stopTimes.first)
    }
}
