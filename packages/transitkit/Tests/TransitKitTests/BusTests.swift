import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing
@testable import TransitKit

struct BusDecodingTests {
    let reference = Date(timeIntervalSince1970: 1_793_748_600)

    @Test func decodesTheEndpointsResponse() throws {
        let positions = try JSONDecoder().decode(
            BusPositions.self,
            from: FixtureTransport.fixture("vehicles-bus-midtown")
        )
        #expect(positions.updatedAt == reference.addingTimeInterval(-20))
        #expect(positions.vehicles.count == 15)

        let bus = try #require(positions.vehicles.first { $0.id == "MTA NYCT_7582" })
        #expect(bus.route == "M15")
        #expect(bus.directionId == 1)
        #expect(bus.tripId == "OH_D6-Weekday-SDon-108500_M15_402")
        #expect(bus.coordinate == Coordinate(latitude: 40.73851, longitude: -73.98108))
        #expect(bus.bearing == 209.0)
        #expect(bus.timestamp == reference.addingTimeInterval(-27))
    }

    @Test func decodesNullsAsMissing() throws {
        let json = Data("""
        {"updatedAt": null, "vehicles": [{"id": "MTABC_1", "route": null, "directionId": null, "tripId": null,
         "headsign": null, "lat": 40.7, "lon": -73.9, "bearing": null, "timestamp": null}]}
        """.utf8)
        let positions = try JSONDecoder().decode(BusPositions.self, from: json)
        #expect(positions.updatedAt == nil)
        #expect(positions.dataAge.mayNotBeRealTime(at: reference))
        let bus = try #require(positions.vehicles.first)
        #expect(bus.route == nil && bus.bearing == nil && bus.timestamp == nil)
        #expect(bus.lineBullet(style: nil).text == "Bus")
    }

    @Test func saysWhenTheFeedIsMoreThanAMinuteOld() {
        let positions = BusPositions(updatedAt: reference.addingTimeInterval(-61), vehicles: [])
        #expect(positions.dataAge.mayNotBeRealTime(at: reference))
        #expect(!positions.dataAge.mayNotBeRealTime(at: reference.addingTimeInterval(-2)))
    }
}

struct BusClientTests {
    let bounds = CoordinateBounds(
        southWest: Coordinate(latitude: 40.7303, longitude: -74.0012),
        northEast: Coordinate(latitude: 40.7587, longitude: -73.9778)
    )

    @Test func asksOurServerForTheSnappedArea() async throws {
        let transport = try FixtureTransport(fixture: "vehicles-bus-midtown")
        let positions = try await TransitClient(transport: transport).buses(in: bounds)
        #expect(positions.vehicles.count == 15)

        let request = try #require(transport.requests.first)
        #expect(request.path?.hasPrefix("/api/vehicles/bus?") == true)
        #expect(request.queryItems["bbox"] == "40.72,-74.02,40.76,-73.96")
        #expect(request.headerFields[.userAgent]?.hasPrefix("Express/") == true)
    }

    @Test func retriesA503LikeEveryOtherCall() async throws {
        let transport = try ColdStartTransport(unavailable: 2, fixture: "vehicles-bus-midtown")
        let retry = RetryMiddleware(sleep: { _ in })
        let client = TransitClient(
            baseURL: TransitKit.defaultBaseURL,
            appVersion: "1.0",
            transport: transport,
            retry: retry
        )
        let positions = try await client.buses(in: bounds)
        #expect(positions.vehicles.count == 15)
        #expect(transport.requests == 3)
    }

    @Test func passesOnTheServersErrorMessage() async throws {
        let body = Data(#"{"error": "bus positions are unavailable"}"#.utf8)
        let transport = FixtureTransport(status: .badGateway, body: body)
        await #expect(throws: TransitError.server(statusCode: 502, message: "bus positions are unavailable")) {
            try await TransitClient(transport: transport).buses(in: bounds)
        }
    }

    @Test func readsRouteStylesFromMOTIS() async throws {
        let transport = try FixtureTransport(fixture: "map-routes-midtown")
        let styles = try await TransitClient(transport: transport).busRouteStyles(in: bounds, zoom: 14.5)
        #expect(styles["M14A+"] == BusRouteStyle(
            name: "M14A-SBS",
            color: RGBColor(hex: "6cbe45"),
            textColor: RGBColor(hex: "ffffff")
        ))
        #expect(styles["BxM1"]?.name == "BxM1")
        // The subway's M is a train, not a bus.
        #expect(styles["M"] == nil)
        #expect(styles.count == 12)

        let request = try #require(transport.requests.first)
        #expect(request.path?.hasPrefix("/api/experimental/map/routes?") == true)
        #expect(request.queryItems["min"] == "40.72,-74.02")
        #expect(request.queryItems["max"] == "40.76,-73.96")
    }
}

struct BusBoundingBoxTests {
    @Test func snapsOutwardToTheGrid() {
        let bounds = CoordinateBounds(
            southWest: Coordinate(latitude: 40.7303, longitude: -74.0012),
            northEast: Coordinate(latitude: 40.7587, longitude: -73.9778)
        )
        let snapped = bounds.snapped(toGrid: 0.02)
        #expect(snapped.southWest == Coordinate(latitude: 40.72, longitude: -74.02))
        #expect(snapped.northEast == Coordinate(latitude: 40.76, longitude: -73.96))
    }

    @Test func nearbyViewsShareOneArea() {
        func view(_ latitude: Double, _ longitude: Double) -> CoordinateBounds {
            CoordinateBounds(
                southWest: Coordinate(latitude: latitude, longitude: longitude),
                northEast: Coordinate(latitude: latitude + 0.012, longitude: longitude + 0.012)
            )
        }
        let first = view(40.7412, -73.9988).snapped(toGrid: 0.02)
        let panned = view(40.7431, -73.9951).snapped(toGrid: 0.02)
        #expect(first == panned)
    }

    @Test func keepsEdgesOnTheGrid() {
        let onGrid = CoordinateBounds(
            southWest: Coordinate(latitude: 40.70, longitude: -74.00),
            northEast: Coordinate(latitude: 40.74, longitude: -73.96)
        )
        #expect(onGrid.snapped(toGrid: 0.02) == onGrid)
    }

    @Test func printsWithoutFloatNoise() {
        let bounds = CoordinateBounds(
            southWest: Coordinate(latitude: 40.6999999, longitude: -73.8100001),
            northEast: Coordinate(latitude: 40.7000001, longitude: -73.8099999)
        )
        let snapped = bounds.snapped(toGrid: 0.01)
        #expect("\(snapped.southWest.latitude),\(snapped.southWest.longitude)" == "40.69,-73.82")
        #expect("\(snapped.northEast.latitude),\(snapped.northEast.longitude)" == "40.71,-73.8")
    }
}

struct BusVisibilityTests {
    let bounds = CoordinateBounds(
        southWest: Coordinate(latitude: 40.73, longitude: -74.00),
        northEast: Coordinate(latitude: 40.76, longitude: -73.97)
    )

    func bus(_ id: String, _ latitude: Double, _ longitude: Double) -> Bus {
        Bus(id: id, route: "M15", coordinate: Coordinate(latitude: latitude, longitude: longitude))
    }

    @Test func hidesBusesWhenZoomedOut() {
        let visibility = VehicleVisibility(minimumZoom: 14)
        let buses = [bus("a", 40.745, -73.985)]
        #expect(visibility.visible(buses, in: bounds, zoom: 13.9).isEmpty)
        #expect(visibility.visible(buses, in: bounds, zoom: 14).map(\.id) == ["a"])
        #expect(!visibility.showsVehicles(atZoom: 13.5))
    }

    @Test func keepsBusesInTheViewport() throws {
        let positions = try JSONDecoder().decode(
            BusPositions.self,
            from: FixtureTransport.fixture("vehicles-bus-midtown")
        )
        let visible = VehicleVisibility(minimumZoom: 14).visible(positions.vehicles, in: bounds, zoom: 15)
        #expect(visible.count == 14)
        #expect(!visible.contains { $0.route == "B57" })
    }

    @Test func thinsToThoseNearestTheMiddle() {
        let buses = [
            bus("edge", 40.731, -73.999),
            bus("middle", 40.745, -73.985),
            bus("near", 40.746, -73.984),
        ]
        let visible = VehicleVisibility(minimumZoom: 14, limit: 2).visible(buses, in: bounds, zoom: 16)
        #expect(Set(visible.map(\.id)) == ["middle", "near"])
    }
}

struct BusHeadingTests {
    let here = Coordinate(latitude: 40.7400, longitude: -73.9900)

    @Test func usesTheFeedsBearing() {
        #expect(Bus(id: "a", route: "M15", coordinate: here, bearing: 209).heading() == 209)
    }

    @Test func normalisesTheBearing() {
        #expect(Bus(id: "a", route: "M15", coordinate: here, bearing: 360).heading() == 0)
        #expect(Bus(id: "a", route: "M15", coordinate: here, bearing: -90).heading() == 270)
        #expect(Bus(id: "a", route: "M15", coordinate: here, bearing: 725).heading() == 5)
    }

    @Test func fallsBackToTheWayItMoved() throws {
        let before = Bus(id: "a", route: "M15", coordinate: here)
        let north = Bus(id: "a", route: "M15", coordinate: Coordinate(latitude: 40.7410, longitude: -73.9900))
        let heading = try #require(north.heading(after: before, previousHeading: 90))
        #expect(heading < 1 || heading > 359)
    }

    @Test func keepsTheLastHeadingThroughGPSNoise() {
        let before = Bus(id: "a", route: "M15", coordinate: here)
        let jitter = Bus(id: "a", route: "M15", coordinate: Coordinate(latitude: 40.74005, longitude: -73.99))
        #expect(jitter.heading(after: before, previousHeading: 119) == 119)
        #expect(jitter.heading(after: before) == nil)
        #expect(jitter.heading() == nil)
    }
}

struct BusRouteStyleTests {
    @Test func namesSelectBusServiceFromTheRouteID() {
        #expect(BusRouteStyle.name(forRouteID: "M15+") == "M15-SBS")
        #expect(BusRouteStyle.name(forRouteID: "M15") == "M15")
        #expect(BusRouteStyle.name(forRouteID: "BxM1") == "BxM1")
    }

    @Test func bulletUsesTheFeedsColours() {
        let bus = Bus(id: "a", route: "M15+", coordinate: Coordinate(latitude: 40.74, longitude: -73.98))
        let style = BusRouteStyle(name: "M15-SBS", color: RGBColor(hex: "0039a6"), textColor: RGBColor(hex: "ffffff"))
        #expect(bus.lineBullet(style: style) == LineBullet(
            text: "M15-SBS",
            shape: .label,
            color: RGBColor(hex: "0039a6"),
            textColor: RGBColor(hex: "ffffff")
        ))
        // Before the styles arrive: the name from the id, in no colour.
        #expect(bus.lineBullet(style: nil) == LineBullet(text: "M15-SBS", shape: .label))
    }
}
