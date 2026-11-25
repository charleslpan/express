import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing
@testable import TransitKit

/// Journey options grouped by route: one row per way there, however many trips take it.
struct JourneyRouteGroupTests {
    /// The W then the M with a change on foot between stations (`plan-union-square-to-williamsburg`).
    static func transfer() throws -> Itinerary {
        try FixtureTransport.firstItinerary("plan-union-square-to-williamsburg")
    }

    /// The Staten Island Railway from Great Kills to St. George: one ride, walking either side.
    static func direct() throws -> Itinerary {
        try FixtureTransport.firstItinerary("plan-great-kills-to-st-george")
    }

    /// The same journey on the next trips of its rides, `minutes` later: other trip ids, other times, another id.
    static func later(_ itinerary: Itinerary, by minutes: Int, rides: (inout Leg) -> Void = { _ in }) -> Itinerary {
        var copy = itinerary
        let shift = TimeInterval(minutes * 60)
        copy.id += "+\(minutes)"
        copy.startTime += shift
        copy.endTime += shift
        for index in copy.legs.indices {
            copy.legs[index] = shifted(copy.legs[index], by: shift)
            if let tripId = copy.legs[index].tripId {
                copy.legs[index].tripId = "\(tripId)+\(minutes)"
                rides(&copy.legs[index])
            }
        }
        return copy
    }

    /// A leg and each stop on it, `shift` seconds later.
    static func shifted(_ leg: Leg, by shift: TimeInterval) -> Leg {
        func place(_ place: Place) -> Place {
            var place = place
            place.arrival = place.arrival?.addingTimeInterval(shift)
            place.departure = place.departure?.addingTimeInterval(shift)
            place.scheduledArrival = place.scheduledArrival?.addingTimeInterval(shift)
            place.scheduledDeparture = place.scheduledDeparture?.addingTimeInterval(shift)
            return place
        }
        var leg = leg
        leg.startTime += shift
        leg.endTime += shift
        leg.scheduledStartTime += shift
        leg.scheduledEndTime += shift
        leg.from = place(leg.from)
        leg.to = place(leg.to)
        leg.intermediateStops = leg.intermediateStops?.map(place)
        return leg
    }

    static func groups(_ itineraries: [Itinerary]) -> [JourneyRouteGroup] {
        JourneyOptions.groups(of: itineraries.map(JourneyOption.init))
    }

    // MARK: Grouping

    @Test func laterTripsOfTheSameRouteShareARow() throws {
        let planned = try Self.transfer()
        let groups = try Self.groups([planned, Self.later(planned, by: 12), Self.later(planned, by: 6)])

        #expect(groups.count == 1)
        let group = try #require(groups.first)
        #expect(group.options.count == 3)
        // The first of the ranking is the row's own; the others come soonest first.
        #expect(group.primary.id == planned.id)
        #expect(group.others.map(\.id) == ["\(planned.id)+6", "\(planned.id)+12"])
        #expect(group.byDeparture.map(\.id) == [planned.id, "\(planned.id)+6", "\(planned.id)+12"])
        // Both rides of the connection are on the pattern, with the change between stations.
        let rides = try #require(group.pattern?.rides)
        #expect(rides.map(\.routeId) == ["us-ny-MTA-NYCSubway_W", "us-ny-MTA-NYCSubway_M"])
        #expect(rides.map(\.boardStopId) == ["us-ny-MTA-NYCSubway_R20S", "us-ny-MTA-NYCSubway_D21S"])
        #expect(rides.map(\.alightStopId) == ["us-ny-MTA-NYCSubway_R22S", "us-ny-MTA-NYCSubway_M16S"])
    }

    @Test func eachDifferenceMakesAnotherRoute() throws {
        let planned = try Self.transfer()
        let changes: [(String, (inout Leg) -> Void)] = [
            ("another line", { $0.routeId = "us-ny-MTA-NYCSubway_R" }),
            ("another direction", { $0.directionId = "0" }),
            ("another boarding stop", { $0.from.stopId = "us-ny-MTA-NYCSubway_R20N" }),
            ("another alighting stop", { $0.to.stopId = "us-ny-MTA-NYCSubway_R23S" }),
        ]
        for (name, change) in changes {
            // Change the first ride only, and then the second: either way it's another route.
            for ride in 0 ..< 2 {
                var other = Self.later(planned, by: 6)
                let index = other.legs.indices.filter { other.legs[$0].tripId != nil }[ride]
                change(&other.legs[index])
                let groups = Self.groups([planned, other])
                #expect(groups.count == 2, "\(name), ride \(ride) grouped with the original")
            }
        }
    }

    @Test func aChangeAtAnotherStationIsAnotherRoute() throws {
        let planned = try Self.transfer()
        // Same two lines, but the first ride gets off one stop later and walks to the same boarding stop.
        let other = Self.later(planned, by: 6) { ride in
            if ride.routeId == "us-ny-MTA-NYCSubway_W" {
                ride.to.stopId = "us-ny-MTA-NYCSubway_R23S"
            }
        }
        #expect(Self.groups([planned, other]).count == 2)
    }

    @Test func rankingOrderIsKept() throws {
        let transfer = try Self.transfer()
        let direct = try Self.direct()
        let groups = Self.groups([
            transfer,
            direct,
            Self.later(transfer, by: 5),
            Self.later(direct, by: 9),
            Self.later(transfer, by: 10),
        ])
        // Each group sits where its best option did, and the later trips fold into it.
        #expect(groups.map(\.primary.id) == [transfer.id, direct.id])
        #expect(groups.map(\.options.count) == [3, 2])
    }

    @Test func identicalRoutesWithoutIdentifiersStayApart() throws {
        let planned = try Self.transfer()
        let withoutRoute = try (0 ..< 2).map { minutes in
            var other = Self.later(planned, by: minutes * 6)
            let index = try #require(other.legs.firstIndex { $0.tripId != nil })
            other.legs[index].routeId = nil
            return other
        }
        #expect(Self.groups(withoutRoute).count == 2)

        let withoutStop = try (0 ..< 2).map { minutes in
            var other = Self.later(planned, by: minutes * 6)
            let index = try #require(other.legs.lastIndex { $0.tripId != nil })
            other.legs[index].to.stopId = nil
            return other
        }
        let groups = Self.groups(withoutStop)
        #expect(groups.count == 2)
        #expect(groups.allSatisfy { $0.pattern == nil && $0.id.hasPrefix("option:") })
        // One without an identifier doesn't pull a complete one in, either.
        #expect(Self.groups([planned, withoutStop[0]]).count == 2)
        #expect(JourneyRoutePattern(withoutRoute[0]) == nil)
    }

    @Test func aWalkIsItsOwnRoute() throws {
        var walk = try Self.direct()
        walk.legs = walk.legs.filter { $0.tripId == nil }
        let pattern = try #require(JourneyRoutePattern(walk))
        #expect(pattern.rides.isEmpty)
        #expect(pattern.id == "walk")
        let ride = try Self.direct()
        #expect(Self.groups([walk, ride]).count == 2)
    }

    @Test func directnessIsOneRide() throws {
        #expect(try #require(JourneyRoutePattern(Self.direct())).isDirect)
        #expect(try !#require(JourneyRoutePattern(Self.transfer())).isDirect)
    }

    @Test func groupsComeFromAPlansOptions() async throws {
        let transport = try FixtureTransport(fixture: "plan-red-hook-to-times-square")
        let response = try await TransitClient(transport: transport).plan(PlanRequest(
            from: .stop(id: "a"),
            to: .stop(id: "b")
        ))
        let itinerary = try #require(response.itineraries.first)
        let options = JourneyOptions.options(
            from: response,
            for: .now,
            now: itinerary.startTime.addingTimeInterval(-600)
        )
        let groups = JourneyOptions.groups(of: options)
        #expect(groups.map(\.primary.id) == options.map(\.id))
    }
}

/// More departures of a single-ride route, checked against their own trips.
struct JourneyDeparturesTests {
    static let railway = "us-ny-MTA-NYCSubway_SI"

    /// A stop's departure on the railway's ride, `minutes` after the planned one leaves.
    static func departure(
        _ tripId: String,
        after minutes: Int,
        from ride: Leg,
        direction: String = "0",
        cancelled: Bool = false
    ) throws -> Departure {
        var departure = try StopTests.firstDeparture()
        let time = ride.startTime.addingTimeInterval(TimeInterval(minutes * 60))
        departure.tripId = tripId
        departure.routeId = ride.routeId ?? ""
        departure.directionId = direction
        departure.mode = ride.mode
        departure.headsign = "St George"
        departure.cancelled = cancelled
        departure.tripCancelled = false
        departure.place.stopId = ride.from.stopId
        departure.place.departure = time
        departure.place.scheduledDeparture = time
        departure.place.arrival = nil
        departure.place.scheduledArrival = nil
        return departure
    }

    /// The planned ride's trip, `minutes` later under another id; calling at the stops the ride does, unless told to
    /// end its run early.
    static func trip(_ id: String, after minutes: Int, of ride: Leg, endsEarly: Bool = false) -> Itinerary {
        var leg = JourneyRouteGroupTests.shifted(ride, by: TimeInterval(minutes * 60))
        leg.tripId = id
        if endsEarly, let stops = leg.intermediateStops {
            leg.to = stops[stops.count / 2]
            leg.intermediateStops = Array(stops[..<(stops.count / 2)])
        }
        return Itinerary(
            duration: leg.duration,
            startTime: leg.startTime,
            endTime: leg.endTime,
            transfers: 0,
            id: id,
            legs: [leg]
        )
    }

    static func ride(of itinerary: Itinerary) throws -> Leg {
        try #require(itinerary.legs.first { $0.tripId != nil })
    }

    @Test func candidatesAreTheSameRouteDirectionAndStop() throws {
        let planned = try JourneyRouteGroupTests.direct()
        let ride = try Self.ride(of: planned)
        let departures = try [
            Self.departure("known", after: 3, from: ride),
            Self.departure("opposite", after: 4, from: ride, direction: "1"),
            Self.departure("cancelled", after: 5, from: ride, cancelled: true),
            Self.departure("c", after: 12, from: ride),
            Self.departure("a", after: 6, from: ride),
            Self.departure("a", after: 6, from: ride), // the same trip twice
            Self.departure("early", after: -4, from: ride),
            Self.departure("b", after: 9, from: ride),
        ]
        var otherRoute = try Self.departure("other-line", after: 7, from: ride)
        otherRoute.routeId = "us-ny-MTA-NYCSubway_L"
        var otherPlatform = try Self.departure("other-stop", after: 8, from: ride)
        otherPlatform.place.stopId = "us-ny-MTA-NYCSubway_S19S"

        let candidates = (departures + [otherRoute, otherPlatform]).upcomingCandidates(
            like: ride,
            excluding: ["known"],
            after: ride.startTime,
            limit: 3
        )
        #expect(candidates.map(\.tripId) == ["a", "b", "c"])
        #expect(departures.upcomingCandidates(like: ride, excluding: [], after: ride.startTime, limit: 2).count == 2)
    }

    @Test func ridingAnotherTripMovesTheWalksWithIt() throws {
        let planned = try JourneyRouteGroupTests.direct()
        let ride = try Self.ride(of: planned)
        let next = JourneyRouteGroupTests.shifted(ride, by: 600)
        let journey = try #require(planned.riding(next))

        #expect(journey.id == "\(planned.id)|\(ride.tripId ?? "")")
        #expect(journey.legs.count == planned.legs.count)
        #expect(journey.startTime == planned.startTime.addingTimeInterval(600))
        #expect(journey.endTime == planned.endTime.addingTimeInterval(600))
        #expect(journey.duration == Int(journey.endTime.timeIntervalSince(journey.startTime)))
        #expect(JourneyRoutePattern(journey) == JourneyRoutePattern(planned))
        // A journey with changes has more than one ride to move: nothing to do.
        let transfer = try JourneyRouteGroupTests.transfer()
        #expect(transfer.riding(next) == nil)
    }

    private static func client(
        departures: [Departure],
        trips: [String: Itinerary],
        counts: Counter = Counter()
    ) -> TransitClient {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return TransitClient(transport: RoutingTransport { request in
            counts.record(request)
            let path = request.path ?? ""
            if path.hasPrefix("/api/v6/stoptimes") {
                let response = DeparturesResponse(
                    stopTimes: departures,
                    place: departures[0].place,
                    previousPageCursor: "",
                    nextPageCursor: ""
                )
                return try encoder.encode(response)
            }
            if path.hasPrefix("/api/v6/trip"), let trip = trips[request.queryItems["tripId"] ?? ""] {
                return try encoder.encode(trip)
            }
            throw URLError(.fileDoesNotExist)
        })
    }

    @Test func upcomingTripsKeepOnlyThoseThatReachTheAlightingStop() async throws {
        let planned = try JourneyRouteGroupTests.direct()
        let ride = try Self.ride(of: planned)
        let counts = Counter()
        let client = try Self.client(
            departures: [
                Self.departure("planned", after: 0, from: ride),
                Self.departure("a", after: 6, from: ride),
                Self.departure("short-turn", after: 9, from: ride),
                Self.departure("b", after: 15, from: ride),
                Self.departure("late", after: 20, from: ride),
            ],
            trips: [
                "a": Self.trip("a", after: 6, of: ride),
                "short-turn": Self.trip("short-turn", after: 9, of: ride, endsEarly: true),
                "b": Self.trip("b", after: 15, of: ride),
                "late": Self.trip("late", after: 20, of: ride),
            ],
            counts: counts
        )
        let journeys = await client.upcomingTrips(
            like: planned,
            excluding: [ride.tripId ?? "", "planned"],
            after: ride.startTime,
            limit: 2
        )

        #expect(journeys.map { try? Self.ride(of: $0).tripId } == ["a", "b"])
        #expect(journeys[0].startTime == planned.startTime.addingTimeInterval(360))
        #expect(journeys[1].startTime == planned.startTime.addingTimeInterval(900))
        #expect(journeys.allSatisfy { JourneyRoutePattern($0) == JourneyRoutePattern(planned) })
        // One stop's departures, then at most the two spare trips beyond the two wanted: never the whole list. The
        // short-turn trip is turned down, and the trip after the two wanted is checked but left over.
        let paths = counts.paths
        #expect(paths.filter { $0.hasPrefix("/api/v6/stoptimes") }.count == 1)
        #expect(paths.filter { $0.hasPrefix("/api/v6/trip") }.count == 4)
        #expect(counts.queries.first?["stopId"] == ride.from.stopId)
    }

    @Test func journeysWithChangesGetNoSupplement() async throws {
        let transfer = try JourneyRouteGroupTests.transfer()
        let counts = Counter()
        let client = Self.client(departures: [], trips: [:], counts: counts)
        let journeys = await client.upcomingTrips(like: transfer, excluding: [], after: transfer.startTime, limit: 3)
        #expect(journeys.isEmpty)
        #expect(counts.paths.isEmpty)
    }

    @Test func aFailedFetchGivesNothingRatherThanThrowing() async throws {
        let planned = try JourneyRouteGroupTests.direct()
        let client = TransitClient(transport: FixtureTransport(error: URLError(.notConnectedToInternet)))
        let journeys = await client.upcomingTrips(like: planned, excluding: [], after: planned.startTime, limit: 3)
        #expect(journeys.isEmpty)
    }
}

/// Records the requests a ``RoutingTransport`` sees.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [HTTPRequest] = []

    func record(_ request: HTTPRequest) {
        lock.withLock { requests.append(request) }
    }

    var paths: [String] {
        lock.withLock { requests.compactMap(\.path) }
    }

    var queries: [[String: String]] {
        lock.withLock { requests.map(\.queryItems) }
    }
}

/// A `ClientTransport` that answers each request from a closure, with the JSON it returns.
struct RoutingTransport: ClientTransport {
    let respond: @Sendable (HTTPRequest) throws -> Data

    init(_ respond: @escaping @Sendable (HTTPRequest) throws -> Data) {
        self.respond = respond
    }

    func send(
        _ request: HTTPRequest,
        body _: HTTPBody?,
        baseURL _: URL,
        operationID _: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let data = try respond(request)
        var fields = HTTPFields()
        fields[.contentType] = "application/json"
        return (HTTPResponse(status: .ok, headerFields: fields), HTTPBody(data))
    }
}
