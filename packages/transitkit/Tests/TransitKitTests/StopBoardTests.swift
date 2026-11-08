import Foundation
import Testing
@testable import TransitKit

struct StopBoardTests {
    static let fresh = RealtimeDataAge(feedTimestamp: DepartureGroupingTests.now.addingTimeInterval(-20))

    @Test func ordersLinesByModeLineAndDirectionNotBySoonest() throws {
        let board = try StopBoard(
            stopTimes: DepartureGroupingTests.unionSquare(),
            fetchedAt: DepartureGroupingTests.now,
            dataAge: Self.fresh
        )
        #expect(board.lines.map(\.id) == [
            "us-ny-MTA-NYCSubway_5|0",
            "us-ny-MTA-NYCSubway_6|0", // the local before its express variant
            "us-ny-MTA-NYCSubway_6|1",
            "us-ny-MTA-NYCSubway_6X|0",
            "us-ny-MTA-NYCSubway_L|0",
            "us-ny-MTA-NYCSubway_L|1",
            "us-ny-MTA-NYCSubway_N|1",
            "us-ny-MTA-NYCSubway_Q|0",
            "us-ny-MTA-NYCSubway_R|0",
        ])
        #expect(!board.isEmpty)
    }

    @Test func putsTheSubwayBeforeBusesAndSortsLinesNaturally() throws {
        let subway = try StopTests.firstDeparture()
        func line(_ name: String, mode: TransitMode, direction: String, minutes: Int) -> Departure {
            var departure = DepartureGroupingTests.copy(of: subway, shiftedBy: minutes)
            departure.routeShortName = name
            departure.displayName = name
            departure.routeId = mode == .subway ? "us-ny-MTA-NYCSubway_\(name)" : "us-ny-MTA-BusManhattan_\(name)"
            departure.mode = mode
            departure.directionId = direction
            departure.tripId = "\(name)-\(direction)-\(minutes)"
            return departure
        }
        let departures = [
            line("M14D-SBS", mode: .bus, direction: "0", minutes: 1),
            line("M101", mode: .bus, direction: "0", minutes: 2),
            line("M9", mode: .bus, direction: "1", minutes: 3),
            line("M9", mode: .bus, direction: "0", minutes: 4),
            line("L", mode: .subway, direction: "1", minutes: 5),
            line("4", mode: .subway, direction: "0", minutes: 6),
        ]
        let lines = departures.stopBoardLines(at: DepartureGroupingTests.now)
        #expect(lines.map { "\($0.bullet.text)|\($0.directionId)" } == [
            "4|0", "L|1", "M9|0", "M9|1", "M14D-SBS|0", "M101|0",
        ])
    }

    @Test func keepsUpToTheLimitPerLineAndDropsDeparted() throws {
        var departures = try DepartureGroupingTests.unionSquare()
        let first = try #require(departures.first { $0.routeId == "us-ny-MTA-NYCSubway_L" && $0.directionId == "1" })
        for minutes in [4, 8, 12, 16, 20] {
            departures.append(DepartureGroupingTests.copy(of: first, shiftedBy: minutes))
        }
        let board = StopBoard(stopTimes: departures, fetchedAt: DepartureGroupingTests.now, dataAge: Self.fresh)
        let canarsie = try #require(board.lines.first { $0.id == "us-ny-MTA-NYCSubway_L|1" })
        #expect(canarsie.departures.count == StopBoard.departuresPerLine)

        // An hour later every departure in the fixture has left: no more departures.
        let later = StopBoard(
            stopTimes: departures,
            fetchedAt: DepartureGroupingTests.now.addingTimeInterval(3600),
            dataAge: Self.fresh
        )
        #expect(later.isEmpty)
        #expect(later.distinctLines.isEmpty)
    }

    @Test func distinctLinesListEachLineOnceInBoardOrder() throws {
        let board = try StopBoard(
            stopTimes: DepartureGroupingTests.unionSquare(),
            fetchedAt: DepartureGroupingTests.now,
            dataAge: Self.fresh
        )
        #expect(board.distinctLines.map(\.bullet.text) == ["5", "6", "6", "L", "N", "Q", "R"])
        #expect(board.distinctLines.map(\.bullet.shape) == [
            .circle, .circle, .diamond, .circle, .circle, .circle, .circle,
        ])
    }

    @Test func mayNotBeRealTimeAfterAMinuteOrWithOldData() throws {
        let stopTimes = try DepartureGroupingTests.unionSquare()
        let now = DepartureGroupingTests.now
        let board = StopBoard(stopTimes: stopTimes, fetchedAt: now, dataAge: Self.fresh)
        #expect(!board.mayNotBeRealTime(at: now.addingTimeInterval(30)))
        #expect(board.mayNotBeRealTime(at: now.addingTimeInterval(61)))
        let old = StopBoard(stopTimes: stopTimes, fetchedAt: now, dataAge: RealtimeDataAge(feedTimestamp: nil))
        #expect(old.mayNotBeRealTime(at: now))
    }

    @Test func requestLooksAheadAnHourAndAHalf() {
        let request = StopBoard.request(stopId: "us-ny-MTA-NYCSubway_635", modes: [.subway, .bus])
        #expect(request.stopId == "us-ny-MTA-NYCSubway_635")
        #expect(request.count == StopBoard.minimumCount)
        #expect(request.window == TimeInterval(90 * 60))
        #expect(request.transitModes == [.subway, .bus])
    }
}

struct TripProgressTests {
    static func trip() throws -> Itinerary {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Itinerary.self, from: FixtureTransport.fixture("trip-6x-pelham-bay-park"))
    }

    static func time(_ string: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: "2026-11-03T\(string)Z"))
    }

    @Test func beforeTheFirstDepartureNothingIsPassed() throws {
        let progress = try TripProgress(trip: Self.trip(), at: Self.time("20:50:00"))
        #expect(progress.phase == .notStarted)
        #expect(progress.passedCount == 0)
        #expect(progress.vehicle == nil)
        #expect(progress.nextStop?.name == "Brooklyn Bridge-City Hall")
        #expect(progress.stops.count == 29)
    }

    @Test func stopsCountAsPassedOnceTheVehicleLeavesThem() throws {
        // 21:05:30, between Astor Pl (left 21:04) and 14 St-Union Sq (due 21:07).
        let progress = try TripProgress(trip: Self.trip(), at: Self.time("21:05:30"))
        #expect(progress.phase == .running)
        #expect(progress.passedCount == 5)
        #expect(progress.isPassed(4))
        #expect(!progress.isPassed(5))
        #expect(progress.nextStop?.name == "14 St-Union Sq")
        let vehicle = try #require(progress.vehicle)
        #expect(vehicle.fromIndex == 4)
        #expect(vehicle.toIndex == 5)
        #expect(!vehicle.isAtStop)
        // Half way in time, on the track between the two stations, heading roughly north.
        let astor = progress.stops[4].place.coordinate
        let union = progress.stops[5].place.coordinate
        #expect(vehicle.coordinate.latitude > astor.latitude)
        #expect(vehicle.coordinate.latitude < union.latitude)
        #expect(vehicle.bearing < 60 || vehicle.bearing > 300)
    }

    @Test func aStopLeftAtExactlyNowIsPassed() throws {
        let progress = try TripProgress(trip: Self.trip(), at: Self.time("21:04:00"))
        #expect(progress.passedCount == 5)
        #expect(progress.vehicle?.fromIndex == 4)
    }

    @Test func aVehicleThatHasArrivedButNotLeftStandsAtTheStop() throws {
        var trip = try Self.trip()
        // Hold the train at 14 St-Union Sq for two minutes.
        let union = try Self.time("21:07:00")
        trip.legs[0].intermediateStops?[4].departure = union.addingTimeInterval(120)
        let progress = TripProgress(trip: trip, at: union.addingTimeInterval(30))
        #expect(progress.passedCount == 5)
        let vehicle = try #require(progress.vehicle)
        #expect(vehicle.isAtStop)
        #expect(vehicle.fromIndex == 5)
        #expect(vehicle.coordinate == progress.stops[5].place.coordinate)
    }

    @Test func passedStopsHaveNoGapsWhateverTheirOwnTimesSay() throws {
        var trip = try Self.trip()
        // A stale prediction leaves Spring St "later" than Bleecker St.
        trip.legs[0].intermediateStops?[1].departure = try Self.time("21:30:00")
        let progress = try TripProgress(trip: trip, at: Self.time("21:03:00"))
        #expect(progress.passedCount == 4)
        #expect((0 ..< 4).allSatisfy(progress.isPassed))
    }

    @Test func afterTheLastArrivalTheTripHasEnded() throws {
        let progress = try TripProgress(trip: Self.trip(), at: Self.time("21:56:00"))
        #expect(progress.phase == .ended)
        #expect(progress.passedCount == 29)
        #expect(progress.vehicle == nil)
        #expect(progress.nextStop == nil)
    }

    @Test func aTripWithNoStopsHasEnded() throws {
        var trip = try Self.trip()
        trip.legs = []
        let progress = try TripProgress(trip: trip, at: Self.time("21:00:00"))
        #expect(progress.phase == .ended)
        #expect(progress.stops.isEmpty)
    }

    @Test func withoutATrackTheVehicleRunsStraightBetweenStops() throws {
        var trip = try Self.trip()
        trip.legs[0].legGeometry.points = ""
        let progress = try TripProgress(trip: trip, at: Self.time("21:05:30"))
        let vehicle = try #require(progress.vehicle)
        let astor = progress.stops[4].place.coordinate
        let union = progress.stops[5].place.coordinate
        #expect(abs(vehicle.coordinate.latitude - (astor.latitude + union.latitude) / 2) < 0.000_01)
    }

    @Test func stopTimesAndDelays() throws {
        let progress = try TripProgress(trip: Self.trip(), at: Self.time("21:05:30"))
        let astor = progress.stops[4]
        #expect(!astor.isRealtime)
        #expect(astor.delayMinutes == nil)
        #expect(astor.status() == .scheduled)
        let union = progress.stops[5]
        #expect(union.isRealtime)
        #expect(union.delayMinutes == 2)
        #expect(union.status() == .late(minutes: 2))
        #expect(union.status(realtimeIsStale: true) == .uncertain)
        #expect(try union.time == (Self.time("21:07:00")))
        #expect(try union.scheduledTime == (Self.time("21:05:00")))
        let first = progress.stops[0]
        #expect(try first.time == (Self.time("20:57:00")))
        #expect(try progress.stops[28].leaveTime == (Self.time("21:56:00")))
    }

    @Test func notFoundIsA404() {
        #expect(TransitError.server(statusCode: 404, message: nil).isNotFound)
        #expect(!TransitError.server(statusCode: 500, message: nil).isNotFound)
        #expect(!TransitError.offline.isNotFound)
    }
}

struct DelayFormatTests {
    @Test func statusFromDelay() {
        #expect(DepartureStatus(delayMinutes: 3, isRealtime: true, isCancelled: false) == .late(minutes: 3))
        #expect(DepartureStatus(delayMinutes: -2, isRealtime: true, isCancelled: false) == .early(minutes: 2))
        // Under the threshold reads as on time.
        #expect(DepartureStatus(delayMinutes: 1, isRealtime: true, isCancelled: false) == .onTime)
        #expect(DepartureStatus(delayMinutes: -1, isRealtime: true, isCancelled: false) == .onTime)
        #expect(DepartureStatus(delayMinutes: nil, isRealtime: true, isCancelled: false) == .onTime)
        #expect(DepartureStatus(delayMinutes: 5, isRealtime: false, isCancelled: false) == .scheduled)
        #expect(DepartureStatus(delayMinutes: 5, isRealtime: true, isCancelled: true) == .cancelled)
        #expect(
            DepartureStatus(delayMinutes: 5, isRealtime: true, isCancelled: false, realtimeIsStale: true) == .uncertain
        )
    }

    @Test func shortText() {
        #expect(DepartureStatus.late(minutes: 3).shortText == "+3 min")
        #expect(DepartureStatus.early(minutes: 2).shortText == "\u{2212}2 min")
        #expect(DepartureStatus.onTime.shortText == "On time")
        #expect(DepartureStatus.scheduled.shortText == "Sched.")
        #expect(DepartureStatus.cancelled.shortText == "Canc.")
        #expect(DepartureStatus.uncertain.shortText == "Not live")
    }

    @Test func spokenText() {
        #expect(DepartureStatus.late(minutes: 1).spokenText == "1 minute late")
        #expect(DepartureStatus.late(minutes: 4).spokenText == "4 minutes late")
        #expect(DepartureStatus.early(minutes: 2).spokenText == "2 minutes early")
        #expect(DepartureStatus.onTime.spokenText == "on time")
    }

    @Test func longText() {
        #expect(DepartureStatus.late(minutes: 3).text == "3 min late")
        #expect(DepartureStatus.early(minutes: 2).text == "2 min early")
    }
}
