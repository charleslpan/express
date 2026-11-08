import Foundation
import Polyline
import Testing
@testable import TransitKit

struct PolylinePathTests {
    // About 1.1 km north up a meridian, then about 0.85 km east along a parallel.
    let corner = Coordinate(latitude: 40.74, longitude: -73.99)
    var path: PolylinePath {
        PolylinePath([
            Coordinate(latitude: 40.73, longitude: -73.99),
            corner,
            Coordinate(latitude: 40.74, longitude: -73.98),
        ])
    }

    @Test func findsPointsByDistanceNotByVertex() throws {
        let northLeg = Coordinate(latitude: 40.73, longitude: -73.99).distance(to: corner)
        // Half the length lies on the longer, northbound stretch, short of the corner.
        let half = try #require(path.point(atFraction: 0.5))
        #expect(abs(half.coordinate.longitude - -73.99) < 1e-9)
        #expect(half.coordinate.latitude < corner.latitude)
        #expect(abs(Coordinate(latitude: 40.73, longitude: -73.99).distance(to: half.coordinate) - path.length / 2) < 1)
        #expect(try abs(#require(half.bearing) - 0) < 0.01)

        // Past the corner, on the eastbound stretch.
        let later = try #require(path.point(atFraction: (northLeg + 100) / path.length))
        #expect(abs(later.coordinate.latitude - 40.74) < 1e-9)
        #expect(abs(corner.distance(to: later.coordinate) - 100) < 1)
        #expect(try abs(#require(later.bearing) - 90) < 0.01)
    }

    @Test func clampsToTheEnds() throws {
        #expect(try #require(path.point(atFraction: -1)).coordinate == path.coordinates.first)
        #expect(try #require(path.point(atFraction: 2)).coordinate == path.coordinates.last)
    }

    @Test func degeneratePaths() throws {
        #expect(PolylinePath([]).point(atFraction: 0.5) == nil)
        let still = try #require(PolylinePath([corner, corner]).point(atFraction: 0.5))
        #expect(still.coordinate == corner)
        #expect(still.bearing == nil)
    }

    @Test(arguments: [
        (40.75, -73.99, 0.0),
        (40.74, -73.98, 90.0),
        (40.73, -73.99, 180.0),
        (40.74, -74.00, 270.0),
    ])
    func bearings(latitude: Double, longitude: Double, expected: Double) {
        let bearing = corner.bearing(to: Coordinate(latitude: latitude, longitude: longitude))
        // Due east and west along a parallel bend by a few hundredths of a degree on a great circle.
        #expect(abs(bearing - expected) < 0.1)
    }
}

struct TrainRunTests {
    static let start = Date(timeIntervalSince1970: 1_793_748_600)

    /// A Q train's hops: Canal St to Union Sq (4 min), a minute's stop, then on to 34 St (3 min).
    static let segments: [TripSegment] = [
        segment(
            from: TestStop("Canal St", "Q01N", 40.7184, -74.0005),
            to: TestStop("14 St-Union Sq", "R20N", 40.7357, -73.9906),
            departure: 0,
            arrival: 240
        ),
        segment(
            from: TestStop("14 St-Union Sq", "R20N", 40.7357, -73.9906),
            to: TestStop("34 St-Herald Sq", "R17N", 40.7496, -73.9879),
            departure: 300,
            arrival: 480
        ),
        segment(
            from: TestStop("8 St-NYU", "R21N", 40.7305, -73.9925),
            to: TestStop("14 St-Union Sq", "R20N", 40.7357, -73.9906),
            departure: 0,
            arrival: 60,
            trip: "bus",
            mode: "BUS"
        ),
    ]

    var run: TrainRun {
        get throws {
            try #require(TrainRun.runs(from: Self.segments).first)
        }
    }

    @Test func keepsTheSubwayAndGathersHopsByTrip() {
        let runs = TrainRun.runs(from: Self.segments)
        #expect(runs.map(\.id) == ["q-trip"])
        #expect(runs.allSatisfy { $0.hops.count == 2 })
        #expect(TrainRun.runs(from: Self.segments, modes: [.subway, .bus]).count == 2)
    }

    @Test func movesAlongTheTrackByTime() throws {
        let run = try run
        let hop = run.hops[0]
        let halfway = try #require(run.position(at: Self.start.addingTimeInterval(120)))
        let expected = try #require(hop.path.point(atFraction: 0.5))
        #expect(halfway.coordinate == expected.coordinate)
        #expect(halfway.fromStop == "Canal St")
        #expect(halfway.toStop == "14 St-Union Sq")
        #expect(halfway.isRealtime)
        #expect(halfway.bullet.text == "Q")
        // Up Broadway: roughly north-east.
        #expect((0 ... 90).contains(halfway.bearing))

        let quarter = try #require(run.position(at: Self.start.addingTimeInterval(60)))
        #expect(quarter.coordinate == hop.path.point(atFraction: 0.25)?.coordinate)
    }

    @Test func standsAtTheStopBetweenHops() throws {
        let run = try run
        let standing = try #require(run.position(at: Self.start.addingTimeInterval(270)))
        #expect(standing.coordinate == run.hops[1].path.coordinates.first)
        #expect(standing.fromStop == "14 St-Union Sq")
        #expect(standing.toStop == "14 St-Union Sq")
    }

    @Test func isOffTheMapBeforeAndAfterItsHops() throws {
        let run = try run
        #expect(run.position(at: Self.start.addingTimeInterval(-1)) == nil)
        #expect(run.position(at: Self.start) != nil)
        #expect(run.position(at: Self.start.addingTimeInterval(480)) != nil)
        #expect(run.position(at: Self.start.addingTimeInterval(481)) == nil)
    }

    @Test func isOffTheMapWhereAHopIsMissing() throws {
        // The hop between Union Sq and 34 St ran outside the area asked for.
        let gap = [
            Self.segments[0],
            Self.segment(
                from: TestStop("34 St-Herald Sq", "R17N", 40.7496, -73.9879), to: TestStop(
                    "Times Sq-42 St",
                    "R16N",
                    40.7547,
                    -73.9868
                ),
                departure: 480, arrival: 600
            ),
        ]
        let run = try #require(TrainRun.runs(from: gap).first)
        #expect(run.position(at: Self.start.addingTimeInterval(360)) == nil)
    }

    @Test func expressVariantsAreDiamondsWithReadableText() throws {
        let express = Self.segment(
            from: TestStop("Parkchester", "613N", 40.8333, -73.8607), to: TestStop(
                "Castle Hill Av",
                "612N",
                40.8341,
                -73.8510
            ),
            departure: 0, arrival: 60, name: "6X", color: "009952"
        )
        let bullet = try #require(TrainRun.runs(from: [express]).first).bullet
        #expect(bullet.text == "6")
        #expect(bullet.shape == .diamond)
        #expect(bullet.textColor == RGBColor(red: 1, green: 1, blue: 1))
        #expect(try run.bullet.textColor == RGBColor(red: 0, green: 0, blue: 0))
    }

    @Test(arguments: [
        ("f6bc26", true), // N Q R W
        ("fccc0a", true), // the older yellow
        ("009952", false), // 4 5 6
        ("eb6800", false), // B D F M
        ("799534", false), // G
        ("7c858c", false), // L
        ("0062cf", false), // A C E
    ])
    func textOnLineColours(hex: String, isBlack: Bool) throws {
        let text = try #require(RGBColor(hex: hex)).readableTextColor
        #expect(text == (isBlack ? RGBColor(red: 0, green: 0, blue: 0) : RGBColor(red: 1, green: 1, blue: 1)))
    }

    /// A `map/trips` hop, decoded from JSON the way the client decodes the server's.
    static func segment(
        from: TestStop,
        to: TestStop,
        departure: TimeInterval,
        arrival: TimeInterval,
        trip: String = "q-trip",
        name: String = "Q",
        color: String = "f6bc26",
        mode: String = "SUBWAY"
    ) -> TripSegment {
        let formatter = ISO8601DateFormatter()
        // A straight track with a bend halfway, so positions follow the polyline rather than the stops.
        let bend = Coordinate(latitude: (from.latitude + to.latitude) / 2, longitude: from.longitude)
        let polyline = Polyline(coordinates: [
            .init(latitude: from.latitude, longitude: from.longitude),
            .init(latitude: bend.latitude, longitude: bend.longitude),
            .init(latitude: to.latitude, longitude: to.longitude),
        ]).encodedPolyline
        let json: [String: Any] = [
            "trips": [["tripId": trip, "displayName": name]],
            "routeColor": color,
            "mode": mode,
            "distance": 0,
            "from": [
                "name": from.name,
                "stopId": "us-ny-MTA-NYCSubway_\(from.id)",
                "lat": from.latitude,
                "lon": from.longitude,
            ],
            "to": ["name": to.name, "stopId": "us-ny-MTA-NYCSubway_\(to.id)", "lat": to.latitude, "lon": to.longitude],
            "departure": formatter.string(from: start.addingTimeInterval(departure)),
            "arrival": formatter.string(from: start.addingTimeInterval(arrival)),
            "scheduledDeparture": formatter.string(from: start.addingTimeInterval(departure)),
            "scheduledArrival": formatter.string(from: start.addingTimeInterval(arrival)),
            "realTime": true,
            "polyline": polyline,
        ]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // swiftlint:disable:next force_try
        return try! decoder.decode(TripSegment.self, from: JSONSerialization.data(withJSONObject: json))
    }
}

/// A subway stop for ``TrainRunTests/segment(from:to:departure:arrival:trip:name:color:mode:)``.
struct TestStop {
    var name: String
    var id: String
    var latitude: Double
    var longitude: Double

    init(_ name: String, _ id: String, _ latitude: Double, _ longitude: Double) {
        self.name = name
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
    }
}

struct TrainVisibilityTests {
    let bounds = CoordinateBounds(
        southWest: Coordinate(latitude: 40.70, longitude: -74.02),
        northEast: Coordinate(latitude: 40.80, longitude: -73.92)
    )

    func train(_ id: String, _ latitude: Double, _ longitude: Double) -> TrainPosition {
        TrainPosition(
            id: id,
            bullet: LineBullet(text: "1", shape: .circle),
            coordinate: Coordinate(latitude: latitude, longitude: longitude),
            bearing: 0,
            fromStop: "A",
            toStop: "B",
            isRealtime: true
        )
    }

    @Test func hidesEveryTrainWhenZoomedOut() {
        let visibility = TrainVisibility(minimumZoom: 13)
        let trains = [train("a", 40.75, -73.97)]
        #expect(visibility.visible(trains, in: bounds, zoom: 12.9).isEmpty)
        #expect(visibility.visible(trains, in: bounds, zoom: 13).map(\.id) == ["a"])
        #expect(!visibility.showsTrains(atZoom: 11))
    }

    @Test func keepsTrainsInsideTheViewport() {
        let trains = [
            train("inside", 40.75, -73.97),
            train("edge", 40.80, -73.92),
            train("north", 40.81, -73.97),
            train("west", 40.75, -74.03),
        ]
        #expect(TrainVisibility().visible(trains, in: bounds, zoom: 14).map(\.id) == ["inside", "edge"])
    }

    @Test func thinsToThoseNearestTheMiddle() {
        let trains = [
            train("far", 40.71, -74.01),
            train("middle", 40.75, -73.97),
            train("near", 40.76, -73.96),
            train("farther", 40.795, -73.925),
        ]
        let visible = TrainVisibility(limit: 2).visible(trains, in: bounds, zoom: 15)
        #expect(Set(visible.map(\.id)) == ["middle", "near"])
    }

    @Test func padsBoundsOnEverySide() {
        let padded = bounds.padded(by: 0.5)
        #expect(abs(padded.southWest.latitude - 40.65) < 1e-9)
        #expect(abs(padded.northEast.longitude - -73.87) < 1e-9)
        #expect(padded.center == bounds.center)
    }
}

struct TripSegmentClientTests {
    @Test func fetchesTripsInAnAreaAndWindow() async throws {
        let transport = try FixtureTransport(fixture: "map-trips-midtown")
        let client = TransitClient(transport: transport)
        let now = Date(timeIntervalSince1970: 1_793_748_600)
        let bounds = CoordinateBounds(
            southWest: Coordinate(latitude: 40.715, longitude: -74.02),
            northEast: Coordinate(latitude: 40.775, longitude: -73.95)
        )
        let segments = try await client.tripSegments(in: bounds, zoom: 14, from: now, to: now.addingTimeInterval(120))

        let request = try #require(transport.requests.first)
        #expect(request.path?.hasPrefix("/api/v6/map/trips?") == true)
        #expect(request.queryItems["min"] == "40.715,-74.02")
        #expect(request.queryItems["max"] == "40.775,-73.95")
        #expect(request.queryItems["zoom"] == "14.0")
        #expect(request.queryItems["precision"] == "5.0")
        #expect(request.queryItems["startTime"] == "2026-11-03T23:30:00Z")
        #expect(request.queryItems["endTime"] == "2026-11-03T23:32:00Z")

        // Recorded tracks decode at the precision asked for: in New York, rather than off the coast of Africa.
        let positions = TrainRun.runs(from: segments).compactMap { $0.position(at: now) }
        #expect(!positions.isEmpty)
        #expect(positions.allSatisfy { ServiceArea.nyc.contains($0.coordinate) })
    }
}
