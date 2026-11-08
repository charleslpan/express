import Foundation
import Testing
@testable import TransitKit

struct DepartureGroupingTests {
    /// Union Square's departures, a little after 21:05 (the fixture's first ones leave at 21:06).
    static func unionSquare() throws -> [Departure] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try FixtureTransport.fixture("stoptimes-union-square")
        return try decoder.decode(DeparturesResponse.self, from: data).stopTimes
    }

    static let now = Date(timeIntervalSince1970: 1_793_739_930) // 2026-11-03T21:05:30Z

    @Test func groupsByLineAndDirectionSoonestFirst() throws {
        let lines = try Self.unionSquare().groupedByLineAndDirection(at: Self.now)
        #expect(lines.map(\.id) == [
            "us-ny-MTA-NYCSubway_L|1", // 21:06
            "us-ny-MTA-NYCSubway_N|1", // 21:06
            "us-ny-MTA-NYCSubway_5|0", // 21:07 (the 5 before the 6X and L: same minute, sorted by name)
            "us-ny-MTA-NYCSubway_6X|0",
            "us-ny-MTA-NYCSubway_L|0",
            "us-ny-MTA-NYCSubway_6|1", // 21:08
            "us-ny-MTA-NYCSubway_Q|0",
            "us-ny-MTA-NYCSubway_6|0", // 21:09
            "us-ny-MTA-NYCSubway_R|0",
        ])
        let express = try #require(lines.first { $0.routeId == "us-ny-MTA-NYCSubway_6X" })
        #expect(express.headsign == "Pelham Bay Park")
        #expect(express.displayHeadsign == "Pelham Bay Park")
        #expect(express.bullet == LineBullet(
            text: "6",
            shape: .diamond,
            color: RGBColor(hex: "009952"),
            textColor: RGBColor(hex: "ffffff")
        ))
    }

    @Test func keepsEachLinesDeparturesInOrderUpToTheLimit() throws {
        var departures = try Self.unionSquare()
        let first = try #require(departures.first { $0.routeId == "us-ny-MTA-NYCSubway_L" && $0.directionId == "1" })
        // Four more Canarsie-bound L trains, given out of order.
        for minutes in [12, 4, 8, 16] {
            departures.append(Self.copy(of: first, shiftedBy: minutes))
        }
        let lines = departures.groupedByLineAndDirection(at: Self.now, limit: 3)
        let canarsie = try #require(lines.first { $0.id == "us-ny-MTA-NYCSubway_L|1" })
        #expect(canarsie.departures.count == 3)
        #expect(canarsie.departures.compactMap { $0.minutesUntil(from: Self.now) } == [0, 4, 8])
    }

    @Test func dropsDeparturesThatHaveLeftAndCopies() throws {
        let departures = try Self.unionSquare()
        // At 21:07:30 the trains of 21:06 and 21:07 have gone.
        let later = Self.now.addingTimeInterval(120)
        let lines = (departures + departures).groupedByLineAndDirection(at: later)
        #expect(lines.map(\.id) == [
            "us-ny-MTA-NYCSubway_6|1",
            "us-ny-MTA-NYCSubway_Q|0",
            "us-ny-MTA-NYCSubway_6|0",
            "us-ny-MTA-NYCSubway_R|0",
        ])
        #expect(lines.allSatisfy { $0.departures.count == 1 })
    }

    @Test func cancelledDeparturesStayButDoNotLeadTheList() throws {
        var departures = try Self.unionSquare()
        // Cancel the L to Canarsie, the first departure.
        let index = try #require(departures
            .firstIndex { $0.routeId == "us-ny-MTA-NYCSubway_L" && $0.directionId == "1" })
        departures[index].tripCancelled = true
        let lines = departures.groupedByLineAndDirection(at: Self.now)
        #expect(lines.first?.id == "us-ny-MTA-NYCSubway_N|1")
        let canarsie = try #require(lines.last)
        #expect(canarsie.id == "us-ny-MTA-NYCSubway_L|1")
        #expect(canarsie.next == nil)
        #expect(canarsie.departures.first?.isCancelled == true)
    }

    @Test func selectBusHeadsign() throws {
        var departure = try Self.unionSquare()[0]
        departure.headsign = "SELECT BUS LES DELANCEY-FDR via 14 ST"
        let line = try #require([departure].groupedByLineAndDirection(at: Self.now).first)
        #expect(line.displayHeadsign == "LES DELANCEY-FDR via 14 ST")
    }

    static func copy(of departure: Departure, shiftedBy minutes: Int) -> Departure {
        var copy = departure
        let shift = TimeInterval(minutes * 60)
        copy.tripId += "-\(minutes)"
        copy.place.departure = departure.place.departure?.addingTimeInterval(shift)
        copy.place.scheduledDeparture = departure.place.scheduledDeparture?.addingTimeInterval(shift)
        copy.place.arrival = departure.place.arrival?.addingTimeInterval(shift)
        copy.place.scheduledArrival = departure.place.scheduledArrival?.addingTimeInterval(shift)
        return copy
    }
}

struct DepartureStatusTests {
    @Test func statusFromTheFeed() throws {
        let departures = try DepartureGroupingTests.unionSquare()
        // Predicted 21:07 against 21:05.
        #expect(departures[2].status() == .late(minutes: 2))
        // No realtime data.
        #expect(departures[3].status() == .scheduled)
        // Predicted a minute early: too little to call early.
        #expect(departures[7].status() == .onTime)
    }

    @Test(arguments: [
        (0, DepartureStatus.onTime),
        (1, .onTime),
        (-1, .onTime),
        (2, .late(minutes: 2)),
        (7, .late(minutes: 7)),
        (-2, .early(minutes: 2)),
        (-4, .early(minutes: 4)),
    ])
    func delayThreshold(delay: Int, status: DepartureStatus) throws {
        var departure = try DepartureGroupingTests.unionSquare()[2]
        let scheduled = try #require(departure.place.scheduledDeparture)
        departure.place.departure = scheduled.addingTimeInterval(TimeInterval(delay * 60))
        #expect(departure.status() == status)
    }

    @Test func cancelledAndStale() throws {
        var departure = try DepartureGroupingTests.unionSquare()[2]
        #expect(departure.status(realtimeIsStale: true) == .uncertain)
        departure.cancelled = true
        #expect(departure.status() == .cancelled)
        #expect(departure.status(realtimeIsStale: true) == .cancelled)

        // A timetable time is never uncertain: it never claimed to be live.
        let scheduled = try DepartureGroupingTests.unionSquare()[3]
        #expect(scheduled.status(realtimeIsStale: true) == .scheduled)
    }

    @Test(arguments: [
        (DepartureStatus.onTime, "On time"),
        (.late(minutes: 3), "3 min late"),
        (.early(minutes: 2), "2 min early"),
        (.scheduled, "Scheduled"),
        (.cancelled, "Cancelled"),
        (.uncertain, "May not be real time"),
    ])
    func statusText(status: DepartureStatus, text: String) {
        #expect(status.text == text)
    }

    @Test(arguments: [(-1, "Now"), (0, "Now"), (1, "1 min"), (3, "3 min"), (75, "75 min")])
    func countdown(minutes: Int, text: String) {
        #expect(CountdownFormat.string(minutes: minutes) == text)
    }
}

struct NearbyStopTests {
    static func stops() throws -> [Stop] {
        try JSONDecoder().decode([Stop].self, from: FixtureTransport.fixture("map-stops-union-square"))
    }

    /// The south-east corner of Union Square, by the 4, 5, and 6.
    static let unionSquareSouthEast = Coordinate(latitude: 40.7347, longitude: -73.9897)

    @Test func nearestSubwayStationComesFirst() throws {
        // On Broadway at E 13 St, the bus stops are nearer than the station's platforms.
        let broadway = Coordinate(latitude: 40.73385, longitude: -73.99106)
        let nearby = try Self.stops().nearbyStops(around: broadway, limit: 4)
        #expect(nearby.map(\.name) == ["14 St-Union Sq", "BROADWAY/E 13 ST", "4 AV/E 13 ST", "E 14 ST/IRVING PL"])
        #expect(nearby[0].id == "us-ny-MTA-NYCSubway_635")
        #expect(nearby[0].isSubway)
        #expect(nearby.dropFirst().map(\.distance) == nearby.dropFirst().map(\.distance).sorted())
    }

    @Test func busStopsAcrossTheStreetCountOnce() throws {
        let nearby = try Self.stops().nearbyStops(around: Self.unionSquareSouthEast, limit: 20)
        // Three BROADWAY/E 13 ST poles (one carried by two feeds) and two E 14 ST/IRVING PL poles.
        #expect(nearby.count(where: { $0.name == "BROADWAY/E 13 ST" }) == 1)
        let irving = try #require(nearby.first { $0.name == "E 14 ST/IRVING PL" })
        // The nearer pole, on the square's side of 14 St.
        #expect(irving.id == "us-ny-MTA-BusManhattan_403906")
        #expect(nearby.count == 10)
        #expect(Set(nearby.map(\.id)).count == nearby.count)
    }

    @Test(arguments: [
        ("E 14 ST/IRVING PL", "E 14 St/Irving Pl"),
        ("UNION SQ EAST/E 15 ST", "Union Sq East/E 15 St"),
        ("14 St-Union Sq", "14 St-Union Sq"),
    ])
    func displayName(name: String, display: String) {
        let stop = NearbyStop(id: "1", name: name, modes: [.bus], coordinate: Self.unionSquareSouthEast, distance: 0)
        #expect(stop.displayName == display)
    }

    @Test(arguments: [(0.0, 1), (40, 1), (64, 1), (65, 2), (330, 6)])
    func walkingMinutes(distance: Double, minutes: Int) {
        let stop = NearbyStop(
            id: "1",
            name: "A",
            modes: [.bus],
            coordinate: Self.unionSquareSouthEast,
            distance: distance
        )
        #expect(stop.walkingMinutes == minutes)
    }

    @Test func limit() throws {
        #expect(try Self.stops().nearbyStops(around: Self.unionSquareSouthEast, limit: 3).count == 3)
        #expect([Stop]().nearbyStops(around: Self.unionSquareSouthEast, limit: 3).isEmpty)
    }
}

struct NearbyBoardTests {
    static let unionSquare = NearbyStop(
        id: "us-ny-MTA-NYCSubway_635",
        name: "14 St-Union Sq",
        modes: [.subway],
        coordinate: Coordinate(latitude: 40.7347, longitude: -73.9900),
        distance: 40
    )
    static let quietStop = NearbyStop(
        id: "us-ny-MTA-BusManhattan_400331",
        name: "5 AV/W 17 ST",
        modes: [.bus],
        coordinate: Coordinate(latitude: 40.7377, longitude: -73.9925),
        distance: 380
    )

    static func board(fetchedAt: Date = DepartureGroupingTests.now, feedAge: TimeInterval = 20) throws -> NearbyBoard {
        try NearbyBoard(
            stops: [unionSquare, quietStop],
            departures: [unionSquare.id: DepartureGroupingTests.unionSquare()],
            fetchedAt: fetchedAt,
            dataAge: RealtimeDataAge(feedTimestamp: fetchedAt.addingTimeInterval(-feedAge)),
            linesPerStop: 4
        )
    }

    @Test func keepsStopsWithDepartures() throws {
        let board = try Self.board()
        #expect(board.stops.map(\.stop) == [Self.unionSquare])
        #expect(board.stops[0].lines.count == 4)
        #expect(!board.isEmpty)

        let empty = NearbyBoard(
            stops: [Self.quietStop],
            departures: [:],
            fetchedAt: DepartureGroupingTests.now,
            dataAge: RealtimeDataAge(feedTimestamp: DepartureGroupingTests.now)
        )
        #expect(empty.isEmpty)
    }

    @Test func realTimeForAMinute() throws {
        let board = try Self.board(feedAge: 20)
        let fetched = board.fetchedAt
        #expect(!board.mayNotBeRealTime(at: fetched))
        // The feed was 20 s old at the fetch: at 40 s later it's a minute old, and past that, stale.
        #expect(!board.mayNotBeRealTime(at: fetched.addingTimeInterval(40)))
        #expect(board.mayNotBeRealTime(at: fetched.addingTimeInterval(41)))
    }

    @Test func staleWhenNotRefreshedForAMinute() throws {
        // Fresh feed data, but nothing fetched since: past a minute the board can't claim to be real time.
        let board = try Self.board(feedAge: 0)
        #expect(!board.mayNotBeRealTime(at: board.fetchedAt.addingTimeInterval(60)))
        #expect(board.mayNotBeRealTime(at: board.fetchedAt.addingTimeInterval(61)))
    }

    @Test func staleFeedOrUnknownAge() throws {
        #expect(try Self.board(feedAge: 90).mayNotBeRealTime(at: DepartureGroupingTests.now))
        var board = try Self.board()
        board.dataAge = RealtimeDataAge(feedTimestamp: nil)
        #expect(board.mayNotBeRealTime(at: DepartureGroupingTests.now))
    }
}

struct StubTransportTests {
    @Test func answersFromTheClosure() async throws {
        let client = TransitClient(transport: StubTransport { request in
            #expect(request.path == "/api/v6/stoptimes")
            #expect(request.query["stopId"] == "us-ny-MTA-NYCSubway_635")
            return try FixtureTransport.fixture("stoptimes-union-square")
        })
        let response = try await client.departures(DeparturesRequest(stopId: "us-ny-MTA-NYCSubway_635"))
        #expect(response.stopTimes.count == 9)
    }

    @Test func servesMetrics() async throws {
        let client = TransitClient(transport: StubTransport { request in
            #expect(request.path == "/metrics")
            return Data("nigiri_gtfsrt_feed_timestamp_seconds{tag=\"us-ny-MTA-NYCSubway-ace\"} 1793739900\n".utf8)
        })
        let age = try await client.realtimeDataAge()
        #expect(age.feedTimestamp == Date(timeIntervalSince1970: 1_793_739_900))
    }

    @Test func failsLikeTheNetwork() async {
        let client = TransitClient(transport: StubTransport { _ in throw URLError(.notConnectedToInternet) })
        await #expect(throws: TransitError.offline) {
            try await client.departures(DeparturesRequest(stopId: "us-ny-MTA-NYCSubway_635"))
        }
    }
}
