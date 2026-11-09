import Foundation
import Testing
@testable import TransitKit

struct JourneyRefreshTests {
    static func date(_ string: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: string))
    }

    /// A ride on the uptown 6X from Spring St to 23 St, as planned before the 6X fell behind: every time on the
    /// timetable, without realtime data.
    private static func plannedRide() throws -> (itinerary: Itinerary, trip: Itinerary) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let trip = try decoder.decode(Itinerary.self, from: FixtureTransport.fixture("trip-6x-pelham-bay-park"))
        let tripLeg = try #require(trip.legs.first)
        let stops = [tripLeg.from] + (tripLeg.intermediateStops ?? []) + [tripLeg.to]

        var itinerary = try FixtureTransport.firstItinerary("plan-red-hook-to-times-square")
        var walk = itinerary.legs[4]
        var ride = tripLeg
        ride.from = stops[2]
        ride.to = stops[6]
        ride.intermediateStops = Array(stops[3 ..< 6])
        ride.startTime = try #require(stops[2].scheduledDeparture)
        ride.scheduledStartTime = ride.startTime
        ride.endTime = try #require(stops[6].scheduledArrival)
        ride.scheduledEndTime = ride.endTime
        ride.realTime = false
        walk.startTime = ride.endTime
        walk.endTime = ride.endTime.addingTimeInterval(TimeInterval(walk.duration))
        itinerary.legs = [ride, walk]
        itinerary.startTime = ride.startTime
        itinerary.endTime = walk.endTime
        itinerary.duration = Int(walk.endTime.timeIntervalSince(ride.startTime))
        return (itinerary, trip)
    }

    @Test func refreshTakesTheTripsLiveTimes() throws {
        let (itinerary, trip) = try Self.plannedRide()
        let tripId = try #require(itinerary.legs[0].tripId)
        let refreshed = itinerary.refreshed(withTrips: [tripId: trip])

        let ride = refreshed.legs[0]
        #expect(ride.from.name == "Spring St")
        #expect(ride.to.name == "23 St-Baruch College")
        #expect(ride.intermediateStops?.map(\.name) == ["Bleecker St", "Astor Pl", "14 St-Union Sq"])
        #expect(ride.realTime)
        // Predicted 21:09 at 23 St, scheduled 21:07: the walk after it moves two minutes later, and the journey too.
        #expect(try ride.endTime == Self.date("2026-11-03T21:09:00Z"))
        #expect(ride.arrivalDelayMinutes == 2)
        #expect(refreshed.legs[1].startTime == ride.endTime)
        #expect(refreshed.endTime == itinerary.endTime.addingTimeInterval(120))
        #expect(refreshed.duration == itinerary.duration + 120)
        #expect(refreshed.id == itinerary.id)

        let plan = JourneyPlan(refreshed)
        #expect(plan.rides[0].alight.status() == .late(minutes: 2))
        #expect(plan.rides[0].direction == "Uptown & The Bronx")
    }

    @Test func refreshPicksUpACancellation() throws {
        let (itinerary, planned) = try Self.plannedRide()
        var trip = planned
        trip.legs[0].cancelled = true
        let tripId = try #require(itinerary.legs[0].tripId)
        let plan = JourneyPlan(itinerary.refreshed(withTrips: [tripId: trip]))
        #expect(plan.problem == .cancelled(plan.rides[0]))
    }

    @Test func refreshKeepsARideItsTripNoLongerServes() throws {
        let (itinerary, trip) = try Self.plannedRide()
        var reversed = itinerary
        // Alighting before boarding: not this trip's order, so the ride stays as planned.
        let from = reversed.legs[0].from
        reversed.legs[0].from = reversed.legs[0].to
        reversed.legs[0].to = from
        let tripId = try #require(itinerary.legs[0].tripId)
        #expect(reversed.refreshed(withTrips: [tripId: trip]) == reversed)
        #expect(itinerary.refreshed(withTrips: [:]) == itinerary)
    }

    @Test func refreshRidesFetchesEachTrip() async throws {
        let (itinerary, _) = try Self.plannedRide()
        let transport = try FixtureTransport(fixture: "trip-6x-pelham-bay-park")
        let client = TransitClient(transport: transport)
        let refreshed = try await client.refreshRides(of: itinerary)
        #expect(refreshed.legs[0].realTime)
        #expect(transport.requests.count == 1)
        #expect(transport.requests.first?.queryItems["tripId"] == itinerary.legs[0].tripId)
    }

    @Test func refreshRidesFailsOnlyWhenEveryTripFails() async throws {
        let (itinerary, _) = try Self.plannedRide()
        let client = TransitClient(transport: FixtureTransport(error: URLError(.notConnectedToInternet)))
        await #expect(throws: TransitError.offline) {
            try await client.refreshRides(of: itinerary)
        }
    }
}
