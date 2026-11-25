import Foundation
import Testing
@testable import TransitKit

struct RideVehicleTests {
    static func date(_ string: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: string))
    }

    /// The 6X's trip from Brooklyn Bridge to Pelham Bay Park, 20:57 to 21:56 UTC, live from 14 St-Union Sq on.
    static func trip() throws -> Itinerary {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Itinerary.self, from: FixtureTransport.fixture("trip-6x-pelham-bay-park"))
    }

    static let busTripId = "20261103_15:57_us-ny-MTA-BusManhattan_OH_D6-Weekday-SDon-108500_M15_402"
    static let busFeedTripId = "OH_D6-Weekday-SDon-108500_M15_402"

    /// The same leg as a northbound M15 bus ride on the same track and times.
    static func busRide() throws -> TrackedRide {
        var leg = try #require(trip().tripLeg)
        leg.mode = .bus
        leg.tripId = busTripId
        leg.routeId = "us-ny-MTA-BusManhattan_M15"
        leg.routeShortName = "M15"
        leg.displayName = "M15"
        leg.directionId = "0"
        return try #require(TrackedRide(leg: leg))
    }

    static func bus(
        _ id: String = "MTA NYCT_1",
        route: String? = "M15",
        direction: Int? = 0,
        tripId: String? = nil,
        at coordinate: Coordinate
    ) -> Bus {
        Bus(id: id, route: route, directionId: direction, tripId: tripId, coordinate: coordinate)
    }

    /// Where the timetable puts the bus ride at `time`.
    static func timetabled(_ ride: TrackedRide, at time: Date) -> Coordinate {
        let fraction = time.timeIntervalSince(ride.start) / ride.end.timeIntervalSince(ride.start)
        return PolylinePath(ride.path).point(atFraction: fraction)!.coordinate
    }

    // MARK: Which legs are rides

    @Test func aRideNeedsATripAndALiveMode() throws {
        let leg = try #require(Self.trip().tripLeg)
        let ride = try #require(TrackedRide(leg: leg))
        #expect(ride.route == "6X")
        #expect(ride.directionId == 0)
        #expect(ride.bullet.text == "6")

        var walk = leg
        walk.mode = .walk
        walk.tripId = nil
        #expect(TrackedRide(leg: walk) == nil)

        var noIdentity = leg
        noIdentity.tripId = nil
        #expect(TrackedRide(leg: noIdentity) == nil)
        noIdentity.tripId = ""
        #expect(TrackedRide(leg: noIdentity) == nil)

        var cancelled = leg
        cancelled.cancelled = true
        #expect(TrackedRide(leg: cancelled) == nil)

        var rail = leg
        rail.mode = .regionalRail
        #expect(TrackedRide(leg: rail) == nil)
    }

    @Test func spellsATripIdAsTheBusFeedDoes() {
        #expect(TrackedRide.feedTripId(fromMOTIS: Self.busTripId) == Self.busFeedTripId)
        #expect(TrackedRide.feedTripId(fromMOTIS: "fixture-trip-6") == nil)
        #expect(TrackedRide.feedTripId(fromMOTIS: Self.busFeedTripId) == nil)
        #expect(TrackedRide.feedTripId(fromMOTIS: "20261103_15:57_us-ny-MTA-BusManhattan_") == nil)
    }

    // MARK: Buses

    @Test func aBusReportingTheTripIsTheRidesBus() throws {
        let ride = try Self.busRide()
        let now = try Self.date("2026-11-03T21:20:00Z")
        let far = Coordinate(latitude: 40.9, longitude: -73.8)
        let buses = [
            Self.bus("other", tripId: "MQ_D6-Weekday-SDon-108100_M14AD_801", at: Self.timetabled(ride, at: now)),
            Self.bus("ours", route: "M101", direction: 1, tripId: Self.busFeedTripId, at: far),
        ]
        let match = try #require(ride.bus(among: buses, at: now))
        #expect(match.bus.id == "ours")
        #expect(match.evidence == .tripId)
    }

    @Test func aBusWithNoTripMustFitRouteDirectionAndPlace() throws {
        let ride = try Self.busRide()
        let now = try Self.date("2026-11-03T21:20:00Z")
        let onTime = Self.timetabled(ride, at: now)
        let ahead = Self.timetabled(ride, at: now.addingTimeInterval(120))

        let match = try #require(ride.bus(among: [Self.bus("near", at: onTime)], at: now))
        #expect(match.bus.id == "near")
        #expect(match.evidence == .routeDirectionAndPlace)

        // The one nearest the timetable wins among those that fit.
        let candidates = [Self.bus("ahead", at: ahead), Self.bus("on-time", at: onTime)]
        #expect(ride.bus(among: candidates, at: now)?.bus.id == "on-time")

        let wrongRoute = Self.bus(route: "M101", at: onTime)
        let wrongDirection = Self.bus(direction: 1, at: onTime)
        let noDirection = Self.bus(direction: nil, at: onTime)
        let otherTrip = Self.bus(tripId: "MQ_D6-Weekday-SDon-108100_M15_801", at: onTime)
        let offTrack = Self.bus(at: Coordinate(latitude: onTime.latitude, longitude: onTime.longitude + 0.01))
        let tenMinutesLate = Self.bus(at: Self.timetabled(ride, at: now.addingTimeInterval(-600)))
        for candidate in [wrongRoute, wrongDirection, noDirection, otherTrip, offTrack, tenMinutesLate] {
            #expect(ride.bus(among: [candidate], at: now) == nil)
        }
    }

    @Test func aRideWithoutADirectionOrRouteFindsNoBusWithoutItsTrip() throws {
        var ride = try Self.busRide()
        let now = try Self.date("2026-11-03T21:20:00Z")
        let bus = Self.bus(at: Self.timetabled(ride, at: now))
        ride.directionId = nil
        #expect(ride.bus(among: [bus], at: now) == nil)
        ride.directionId = 0
        ride.route = nil
        #expect(ride.bus(among: [bus], at: now) == nil)
    }

    @Test func subwayRidesHaveNoBus() throws {
        let ride = try #require(TrackedRide(trip: Self.trip()))
        let now = try Self.date("2026-11-03T21:20:00Z")
        let bus = Self.bus(route: "6X", tripId: "L0S2-6-1092-S01_095750_6..N02R", at: Self.timetabled(ride, at: now))
        #expect(ride.bus(among: [bus], at: now) == nil)
    }

    @Test func looksForTheBusAroundWhereTheRideShouldBe() throws {
        let ride = try Self.busRide()
        let now = try Self.date("2026-11-03T21:20:00Z")
        let area = try #require(ride.busSearchArea(at: now))
        #expect(area.contains(Self.timetabled(ride, at: now)))
        #expect(area.northEast.latitude - area.southWest.latitude < 0.04)

        // Before the lead time, and once the rider has got off, there's nothing to look for.
        #expect(try ride.busSearchArea(at: Self.date("2026-11-03T20:20:00Z")) == nil)
        #expect(try ride.busSearchArea(at: Self.date("2026-11-03T22:00:00Z")) == nil)
    }

    @Test func liveTimesPlaceTheSearchBetterThanTheTimetable() throws {
        let trip = try Self.trip()
        let ride = try #require(TrackedRide(trip: trip))
        let now = try Self.date("2026-11-03T21:08:00Z")
        let expected = try #require(ride.expectedCoordinate(at: now, trip: trip))
        let progress = TripProgress(trip: trip, at: now)
        #expect(expected == progress.vehicle?.coordinate)
    }

    // MARK: Trains

    @Test func placesATrainFromLiveTimes() throws {
        let trip = try Self.trip()
        let ride = try #require(TrackedRide(trip: trip))
        let position = try #require(ride.estimatedPosition(in: trip, at: Self.date("2026-11-03T21:08:00Z")))
        #expect(position.fromStop == "14 St-Union Sq")
        #expect(position.toStop == "23 St-Baruch College")
        let from = Coordinate(latitude: 40.734673, longitude: -73.989951)
        #expect(from.distance(to: position.coordinate) < 800)
    }

    @Test func showsNoTrainTheTimetableAloneRuns() throws {
        let trip = try Self.trip()
        let ride = try #require(TrackedRide(trip: trip))
        // Between Bleecker St and Astor Pl, where the times are the timetable's.
        #expect(try ride.estimatedPosition(in: trip, at: Self.date("2026-11-03T21:03:00Z")) == nil)
    }

    @Test func showsNoTrainOutsideTheRidesWindow() throws {
        let trip = try Self.trip()
        let ride = try #require(TrackedRide(trip: trip))
        #expect(try ride.estimatedPosition(in: trip, at: Self.date("2026-11-03T20:20:00Z")) == nil)
        #expect(try ride.estimatedPosition(in: trip, at: Self.date("2026-11-03T21:57:00Z")) == nil)
    }

    @Test func aRidersTrainStopsShowingAfterTheyGetOff() throws {
        let trip = try Self.trip()
        var leg = try #require(trip.tripLeg)
        leg.endTime = try Self.date("2026-11-03T21:09:00Z")
        let ride = try #require(TrackedRide(leg: leg))
        #expect(try ride.estimatedPosition(in: trip, at: Self.date("2026-11-03T21:08:00Z")) != nil)
        #expect(try ride.estimatedPosition(in: trip, at: Self.date("2026-11-03T21:12:00Z")) == nil)
    }
}

struct PolylineNearestTests {
    // About 1.1 km north up a meridian, then about 0.85 km east along a parallel.
    let path = PolylinePath([
        Coordinate(latitude: 40.73, longitude: -73.99),
        Coordinate(latitude: 40.74, longitude: -73.99),
        Coordinate(latitude: 40.74, longitude: -73.98),
    ])

    @Test func findsHowFarAlongAndHowFarOff() throws {
        let onPath = try #require(path.point(atFraction: 0.25)).coordinate
        let on = try #require(path.nearest(to: onPath))
        #expect(abs(on.fraction - 0.25) < 0.001)
        #expect(on.distance < 1)

        // 100 m west of the northbound stretch's middle.
        let beside = Coordinate(latitude: 40.735, longitude: -73.99 - 100 / (111_320 * cos(40.735 * .pi / 180)))
        let near = try #require(path.nearest(to: beside))
        #expect(abs(near.distance - 100) < 1)
        let middle = try #require(path.nearest(to: Coordinate(latitude: 40.735, longitude: -73.99)))
        #expect(abs(near.fraction - middle.fraction) < 0.001)
    }

    @Test func clampsToTheEndsAndHasNothingForAPointlessPath() throws {
        let before = try #require(path.nearest(to: Coordinate(latitude: 40.7, longitude: -73.99)))
        #expect(before.fraction == 0)
        #expect(before.distance > 3000)
        #expect(PolylinePath([]).nearest(to: Coordinate(latitude: 40.7, longitude: -74)) == nil)
        let still = Coordinate(latitude: 40.7, longitude: -74)
        #expect(PolylinePath([still, still]).nearest(to: still) == nil)
    }
}
