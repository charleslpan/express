import Foundation
import Testing
@testable import TransitKit

struct ServiceAreaTests {
    @Test(arguments: [
        ("Times Square", 40.7580, -73.9855),
        ("Tottenville, Staten Island", 40.5126, -74.2510),
        ("Far Rockaway, Queens", 40.6054, -73.7554),
        ("Wakefield, the Bronx", 40.9030, -73.8507),
        ("Jamaica, Queens", 40.7027, -73.7890),
        ("Newark Penn Station", 40.7347, -74.1644),
        ("Hoboken Terminal", 40.7351, -74.0275),
    ])
    func containsNYCAndNearbyNewJersey(place _: String, latitude: Double, longitude: Double) {
        #expect(ServiceArea.nyc.contains(latitude: latitude, longitude: longitude))
        #expect(ServiceArea.nyc.contains(Coordinate(latitude: latitude, longitude: longitude)))
    }

    @Test(arguments: [
        ("Philadelphia", 39.9526, -75.1652),
        ("White Plains", 41.0340, -73.7629),
        ("Mineola, Long Island", 40.7493, -73.6407),
        ("Trenton", 40.2206, -74.7597),
        ("London", 51.5072, -0.1276),
    ])
    func excludesElsewhere(place _: String, latitude: Double, longitude: Double) {
        #expect(!ServiceArea.nyc.contains(latitude: latitude, longitude: longitude))
    }

    @Test func edgesAreInside() {
        let area = ServiceArea(south: 1, west: 2, north: 3, east: 4)
        #expect(area.contains(latitude: 1, longitude: 2))
        #expect(area.contains(latitude: 3, longitude: 4))
        #expect(!area.contains(latitude: 3.0001, longitude: 4))
    }
}

struct RealtimeDataAgeTests {
    static let metrics = """
    # HELP nigiri_gtfsrt_feed_timestamp_seconds Timestamp of the GTFS-RT feed
    # TYPE nigiri_gtfsrt_feed_timestamp_seconds gauge
    nigiri_gtfsrt_feed_timestamp_seconds{tag="us-ny-MTA-NYCSubway"} 1793800000
    nigiri_gtfsrt_feed_timestamp_seconds{tag="us-ny-MTA-BusQueens"} 1793799000
    nigiri_gtfsrt_feed_timestamp_seconds{tag="us-ny-MTA-BusBronx"} 0
    # HELP nigiri_gtfsrt_last_update_timestamp_seconds Last update timestamp of the GTFS-RT feed
    nigiri_gtfsrt_last_update_timestamp_seconds{tag="us-ny-MTA-NYCSubway"} 1793800005
    motis_routing_odm_events_found_bucket{stage="non_dominated",le="0"} 0
    """

    let feedTime = Date(timeIntervalSince1970: 1_793_800_000)

    @Test func parsesEveryFeedsTimestamp() {
        let timestamps = RealtimeDataAge.feedTimestamps(inMetrics: Self.metrics)
        #expect(timestamps.count == 3)
        #expect(timestamps["us-ny-MTA-NYCSubway"] == .some(feedTime))
        #expect(timestamps["us-ny-MTA-BusQueens"] == .some(Date(timeIntervalSince1970: 1_793_799_000)))
        #expect(timestamps["us-ny-MTA-BusBronx"] == .some(nil))
    }

    @Test func readsTheSubwayFeed() {
        let age = RealtimeDataAge(metrics: Self.metrics)
        #expect(age.feedTimestamp == feedTime)
        #expect(age.age(at: feedTime.addingTimeInterval(42)) == 42)
        #expect(age.age(at: feedTime.addingTimeInterval(-5)) == 0)
    }

    @Test func mayNotBeRealTimeAfterAMinute() {
        let age = RealtimeDataAge(feedTimestamp: feedTime)
        #expect(!age.mayNotBeRealTime(at: feedTime.addingTimeInterval(30)))
        #expect(!age.mayNotBeRealTime(at: feedTime.addingTimeInterval(60)))
        #expect(age.mayNotBeRealTime(at: feedTime.addingTimeInterval(61)))
    }

    @Test func unknownAgeMayNotBeRealTime() {
        // A feed the server hasn't fetched yet, a server without our feeds, and an empty answer.
        for age in [
            RealtimeDataAge(metrics: Self.metrics, feedPrefix: "us-ny-MTA-BusBronx"),
            RealtimeDataAge(metrics: Self.metrics, feedPrefix: "us-ny-MTA-NYCFerry"),
            RealtimeDataAge(metrics: ""),
        ] {
            #expect(age.feedTimestamp == nil)
            #expect(age.age(at: feedTime) == nil)
            #expect(age.mayNotBeRealTime(at: feedTime))
        }
    }

    @Test func oldestMatchingFeedWins() {
        let age = RealtimeDataAge(metrics: Self.metrics, feedPrefix: "us-ny-MTA-Bus")
        #expect(age.feedTimestamp == nil) // the Bronx feed has no timestamp yet
        let fetched = Self.metrics.replacingOccurrences(of: "BusBronx\"} 0", with: "BusBronx\"} 1793799500")
        #expect(RealtimeDataAge(metrics: fetched, feedPrefix: "us-ny-MTA-Bus").feedTimestamp
            == Date(timeIntervalSince1970: 1_793_799_000))
    }

    @Test func clientFetchesMetrics() async throws {
        let transport = FixtureTransport(body: Data(Self.metrics.utf8))
        let client = try TransitClient(
            baseURL: #require(URL(string: "https://motis.example")),
            appVersion: "1.2",
            transport: transport
        )
        let age = try await client.realtimeDataAge()
        #expect(age.feedTimestamp == feedTime)
        let request = try #require(transport.requests.first)
        #expect(request.method == .get)
        #expect(request.path == "/metrics")
        #expect(request.headerFields[.userAgent] == "Express/1.2 (https://github.com/charleslpan/express)")
    }

    @Test func clientMapsErrors() async {
        await #expect(throws: TransitError.offline) {
            try await TransitClient(transport: FixtureTransport(error: URLError(.timedOut))).realtimeDataAge()
        }
        await #expect(throws: TransitError.server(statusCode: 404, message: nil)) {
            try await TransitClient(transport: FixtureTransport(status: .notFound)).realtimeDataAge()
        }
    }
}

struct LineBulletTests {
    @Test(arguments: ["6X", "7X", "FX"])
    func expressVariants(route: String) {
        #expect(LineBullet.isExpressVariant(route))
    }

    @Test(arguments: ["6", "F", "GS", "SIR", "X27", "Bx12", "", "X"])
    func notExpressVariants(route: String) {
        #expect(!LineBullet.isExpressVariant(route))
    }

    @Test func subwayLineIsACircleInTheFeedsColours() throws {
        let itinerary = try FixtureTransport.firstItinerary("plan-union-square-to-williamsburg")
        let bullet = try #require(itinerary.legs[1].lineBullet)
        #expect(bullet.shape == .circle)
        #expect(bullet.text == itinerary.legs[1].routeShortName)
        #expect(bullet.color == itinerary.legs[1].routeRGBColor)
        #expect(bullet.textColor == itinerary.legs[1].routeTextRGBColor)
    }

    @Test(arguments: [
        ("6X", "us-ny-MTA-NYCSubway_6X"), ("7X", "us-ny-MTA-NYCSubway_7X"), ("FX", "us-ny-MTA-NYCSubway_FX"),
        ("6", "us-ny-MTA-NYCSubway_6X"), // a feed that names the variant only in its route id
    ])
    func expressVariantIsADiamond(shortName: String, routeId: String) throws {
        var leg = try subwayLeg()
        leg.routeShortName = shortName
        leg.routeId = routeId
        leg.routeColor = "00933c"
        let bullet = try #require(leg.lineBullet)
        #expect(bullet.shape == .diamond)
        #expect(bullet.text == String(shortName.prefix(1)))
        #expect(bullet.color == RGBColor(hex: "00933c"))
    }

    @Test func busAndRailwayAreLabels() throws {
        let bus = try FixtureTransport.firstItinerary("plan-red-hook-to-times-square").legs[1]
        #expect(bus.lineBullet == LineBullet(
            text: "B57",
            shape: .label,
            color: RGBColor(hex: "ee352e"),
            textColor: RGBColor(hex: "ffffff")
        ))
        let railway = try #require(
            FixtureTransport.firstItinerary("plan-great-kills-to-st-george").legs.first { $0.routeShortName == "SIR" }
        )
        #expect(railway.lineBullet?.shape == .label)
        #expect(railway.lineBullet?.text == "SIR")
    }

    @Test func walksHaveNoBullet() throws {
        let walk = try FixtureTransport.firstItinerary("plan-union-square-to-williamsburg").legs[0]
        #expect(walk.lineBullet == nil)
    }

    private func subwayLeg() throws -> Leg {
        let legs = try FixtureTransport.firstItinerary("plan-union-square-to-williamsburg").legs
        return try #require(legs.first { $0.mode == .subway })
    }
}
