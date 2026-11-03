import Foundation
import Testing
@testable import TransitKit

struct HelperTests {
    @Test func polylineDecodesAtTheStatedPrecision() throws {
        let itinerary = try FixtureTransport.firstItinerary("plan-union-square-to-williamsburg")
        let ride = itinerary.legs[1]
        #expect(ride.legGeometry.precision == 6)
        let points = ride.coordinates
        #expect(points.count == ride.legGeometry.length)
        // The path starts at the platform it leaves from and ends where it arrives.
        let first = try #require(points.first)
        let last = try #require(points.last)
        #expect(abs(first.latitude - ride.from.lat) < 0.001 && abs(first.longitude - ride.from.lon) < 0.001)
        #expect(abs(last.latitude - ride.to.lat) < 0.001 && abs(last.longitude - ride.to.lon) < 0.001)
    }

    @Test func polylineKnownPoints() {
        // Google's documented example, encoded at precision 5.
        let polyline = EncodedPolyline(points: "_p~iF~ps|U_ulLnnqC_mqNvxq`@", precision: 5, length: 3)
        #expect(polyline.coordinates == [
            Coordinate(latitude: 38.5, longitude: -120.2),
            Coordinate(latitude: 40.7, longitude: -120.95),
            Coordinate(latitude: 43.252, longitude: -126.453),
        ])
        #expect(EncodedPolyline(points: "", precision: 6, length: 0).coordinates.isEmpty)
    }

    @Test func walkStepsDecode() throws {
        let itinerary = try FixtureTransport.firstItinerary("plan-red-hook-to-times-square")
        let walk = itinerary.legs[0]
        let steps = try #require(walk.steps)
        #expect(!steps.isEmpty)
        #expect(steps.allSatisfy { $0.polyline.precision == 6 && !$0.polyline.coordinates.isEmpty })
    }

    @Test func leavesInMinutes() throws {
        let itinerary = try FixtureTransport.firstItinerary("plan-red-hook-to-times-square")
        let bus = itinerary.legs[1] // departs 20:31:00Z
        let now = try #require(ISO8601DateFormatter().date(from: "2026-11-03T20:26:30Z"))
        #expect(bus.minutesUntilDeparture(from: now) == 4)
        #expect(bus.minutesUntilDeparture(from: now.addingTimeInterval(5 * 60)) == -1)
        #expect(itinerary.minutesUntilDeparture(from: now) == 0)
    }

    @Test(arguments: [
        (0, "0 sec"), (45, "45 sec"), (60, "1 min"), (89, "1 min"), (90, "2 min"),
        (1320, "22 min"), (3600, "1 hr"), (3900, "1 hr 5 min"), (7200, "2 hr"),
    ])
    func durations(seconds: Int, expected: String) {
        #expect(DurationFormat.string(seconds: seconds) == expected)
    }

    @Test func hexColours() {
        #expect(RGBColor(hex: "ff8000") == RGBColor(red: 1, green: 128.0 / 255, blue: 0))
        #expect(RGBColor(hex: "#0062CF") == RGBColor(red: 0, green: 98.0 / 255, blue: 207.0 / 255))
        #expect(RGBColor(hex: "") == nil)
        #expect(RGBColor(hex: "fff") == nil)
        #expect(RGBColor(hex: "gg0000") == nil)
    }
}
