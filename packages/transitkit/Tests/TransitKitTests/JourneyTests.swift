import Foundation
import Testing
@testable import TransitKit

struct JourneyQueryTests {
    static let unionSquare = Coordinate(latitude: 40.7359, longitude: -73.9906)
    static let grandCentral = PlaceDetails(
        placeID: "grand-central",
        name: "Grand Central Terminal",
        coordinate: Coordinate(latitude: 40.7527, longitude: -73.9772)
    )
    static let philadelphia = Coordinate(latitude: 39.9526, longitude: -75.1652)

    @Test func leaveNowFromCurrentLocation() throws {
        let query = JourneyQuery(to: .place(Self.grandCentral))
        #expect(query.from == .currentLocation)
        #expect(query.time == .now)
        #expect(query.needsCurrentLocation)

        let request = try query.planRequest(currentLocation: Self.unionSquare)
        #expect(request.from == .coordinate(Self.unionSquare))
        #expect(request.to == .coordinate(Self.grandCentral.coordinate))
        #expect(request.time == .now)
        #expect(request.transitModes == [.subway, .bus, .regionalRail])
        #expect(request.numberOfItineraries == 5)
        #expect(request.pageCursor == nil)
        #expect(request.query.time == nil)
        #expect(request.query.arriveBy == nil)
    }

    @Test func departAt() throws {
        let departure = Date(timeIntervalSince1970: 1_793_752_200)
        let query = JourneyQuery(to: .place(Self.grandCentral), time: .departAt(departure))
        let request = try query.planRequest(currentLocation: Self.unionSquare)
        #expect(request.time == .departAt(departure))
        #expect(request.query.time == departure)
        #expect(request.query.arriveBy == false)
    }

    @Test func arriveBy() throws {
        let arrival = Date(timeIntervalSince1970: 1_793_755_800)
        let start = PlaceDetails(placeID: "union-square", name: "Union Square", coordinate: Self.unionSquare)
        let query = JourneyQuery(from: .place(start), to: .place(Self.grandCentral), time: .arriveBy(arrival))
        #expect(!query.needsCurrentLocation)
        // Two picked places need no fix at all.
        let request = try query.planRequest(currentLocation: nil)
        #expect(request.from == .coordinate(Self.unionSquare))
        #expect(request.query.time == arrival)
        #expect(request.query.arriveBy == true)
        #expect(request.query.transitModes == [.subway, .bus, .regionalRail])
    }

    @Test func swapEnds() throws {
        var query = JourneyQuery(to: .place(Self.grandCentral))
        query.swapEnds()
        #expect(query.from == .place(Self.grandCentral))
        #expect(query.to == .currentLocation)
        let request = try query.planRequest(currentLocation: Self.unionSquare)
        #expect(request.from == .coordinate(Self.grandCentral.coordinate))
        #expect(request.to == .coordinate(Self.unionSquare))
    }

    @Test func currentLocationWithoutAFix() {
        #expect(throws: JourneyQueryError.locationUnknown) {
            try JourneyQuery(to: .place(Self.grandCentral)).planRequest(currentLocation: nil)
        }
    }

    @Test func outsideTheServiceArea() {
        #expect(throws: JourneyQueryError.outsideServiceArea) {
            try JourneyQuery(to: .place(Self.grandCentral)).planRequest(currentLocation: Self.philadelphia)
        }
        let liberty = PlaceDetails(
            placeID: "liberty-bell",
            name: "Liberty Bell",
            coordinate: Self.philadelphia
        )
        #expect(throws: JourneyQueryError.outsideServiceArea) {
            try JourneyQuery(to: .place(liberty)).planRequest(currentLocation: Self.unionSquare)
        }
    }
}

struct JourneySummaryTests {
    @Test func subwayWithATransfer() throws {
        let itinerary = try FixtureTransport.firstItinerary("plan-union-square-to-williamsburg")
        let summary = JourneySummary(itinerary)

        #expect(summary.id == itinerary.id)
        #expect(summary.departure == itinerary.startTime)
        #expect(summary.arrival == itinerary.endTime)
        #expect(summary.durationSeconds == 1320)
        #expect(summary.formattedDuration == "22 min")
        // 1 + 4 + 1 minutes on foot, the change from the W to the M among them.
        #expect(summary.walkingSeconds == 360)
        #expect(summary.formattedWalking == "6 min")
        #expect(summary.transfers == 1)
        #expect(!summary.isRealtime)
        #expect(summary.firstRideDelayMinutes == nil)
        #expect(!summary.isWalkOnly)
        #expect(summary.tripIDs.count == 2)
        #expect(summary.firstRideDeparture == itinerary.legs[1].startTime)

        let kinds = summary.segments.map { segment -> String in
            switch segment.kind {
            case .walk: "walk \(segment.minutes)"
            case let .ride(bullet, mode): "\(mode.rawValue) \(bullet.text) \(segment.minutes)"
            }
        }
        #expect(kinds == ["walk 1", "SUBWAY W 4", "walk 4", "SUBWAY M 11", "walk 1"])
        #expect(Set(summary.segments.map(\.id)).count == summary.segments.count)
    }

    @Test func busAndSubwayWithRealtime() throws {
        let summary = try JourneySummary(FixtureTransport.firstItinerary("plan-red-hook-to-times-square"))
        #expect(summary.formattedDuration == "55 min")
        #expect(summary.walkingSeconds == 840)
        #expect(summary.transfers == 1)
        #expect(summary.isRealtime)
        // The B57 leaves two minutes early.
        #expect(summary.firstRideDelayMinutes == -2)
        guard case let .ride(bullet, mode) = summary.segments[1].kind else {
            Issue.record("Expected the B57")
            return
        }
        #expect(mode == .bus)
        #expect(bullet.text == "B57")
        #expect(bullet.shape == .label)
        #expect(summary.segments[1].minutes == 21)
    }

    @Test func statenIslandRailwayHasNoTransfers() throws {
        let summary = try JourneySummary(FixtureTransport.firstItinerary("plan-great-kills-to-st-george"))
        #expect(summary.transfers == 0)
        #expect(summary.walkingSeconds == 240)
        #expect(summary.segments.count == 3)
    }

    @Test func minutesUntilDeparture() throws {
        let itinerary = try FixtureTransport.firstItinerary("plan-union-square-to-williamsburg")
        let summary = JourneySummary(itinerary)
        // The W leaves at 20:30; the walk to it starts at 20:29.
        let now = try #require(ISO8601DateFormatter().date(from: "2026-11-03T20:25:30Z"))
        #expect(summary.minutesUntilDeparture(from: now) == 4)
        #expect(summary.minutesUntilDeparture(from: now.addingTimeInterval(3600)) == 0)
    }
}

struct JourneyOptionsTests {
    static let start = Date(timeIntervalSince1970: 1_793_748_600)

    static func summary(
        _ id: String,
        departsIn departure: Int,
        arrivesIn arrival: Int,
        transfers: Int = 0,
        walking: Int = 300
    ) -> JourneySummary {
        JourneySummary(
            id: id,
            departure: start.addingTimeInterval(TimeInterval(departure * 60)),
            arrival: start.addingTimeInterval(TimeInterval(arrival * 60)),
            durationSeconds: (arrival - departure) * 60,
            walkingSeconds: walking,
            transfers: transfers
        )
    }

    static let options = [
        summary("slow", departsIn: 0, arrivesIn: 40),
        summary("late", departsIn: 15, arrivesIn: 35),
        summary("fast", departsIn: 5, arrivesIn: 25, transfers: 1),
        summary("direct", departsIn: 2, arrivesIn: 25),
        summary("walky", departsIn: 1, arrivesIn: 25, walking: 900),
    ]

    @Test func leavingSortsByArrivalThenTransfersThenWalking() {
        let ids = JourneyOptions.sorted(Self.options, for: .now).map(\.id)
        #expect(ids == ["direct", "walky", "fast", "late", "slow"])
        #expect(JourneyOptions.sorted(Self.options, for: .departAt(Self.start)).map(\.id) == ids)
    }

    @Test func arrivingSortsByLatestDeparture() {
        let ids = JourneyOptions.sorted(Self.options, for: .arriveBy(Self.start.addingTimeInterval(2400))).map(\.id)
        // "fast" leaves at 5 minutes, but its change costs 5: it ties "slow" at 0, which has no change.
        #expect(ids == ["late", "direct", "walky", "slow", "fast"])
    }

    // MARK: Ranking by penalised time

    /// A journey whose rides last `rides` minutes each, with the walking between them.
    static func journey(
        _ id: String,
        departsIn departure: Int = 0,
        arrivesIn arrival: Int,
        rides: [Int],
        walking: Int = 300
    ) -> JourneySummary {
        var summary = summary(
            id,
            departsIn: departure,
            arrivesIn: arrival,
            transfers: rides.count - 1,
            walking: walking
        )
        summary.segments = rides.enumerated().map { index, minutes in
            JourneySegment(
                id: "\(id)-\(index)",
                kind: .ride(LineBullet(text: "\(id)\(index)", shape: .circle), .subway),
                minutes: minutes
            )
        }
        return summary
    }

    /// Times Square to Coney Island, as captured: two journeys with two changes (a one-minute train and a
    /// three-minute bus among them) arrive a few minutes before the direct Q.
    static let timesSquareToConeyIsland = [
        journey("shuttle", arrivesIn: 49, rides: [12, 1, 20]),
        journey("bus", arrivesIn: 50, rides: [10, 15, 3]),
        journey("direct-q", arrivesIn: 56, rides: [52]),
    ]

    @Test func directRideBeatsTwoChangesThatArriveMinutesEarlier() {
        // By raw arrival the changes win; with their cost the direct Q leads.
        #expect(Self.timesSquareToConeyIsland.sorted { $0.arrival < $1.arrival }.map(\.id)
            == ["shuttle", "bus", "direct-q"])
        let ids = JourneyOptions.sorted(Self.timesSquareToConeyIsland, for: .now).map(\.id)
        #expect(ids == ["direct-q", "bus", "shuttle"])
        #expect(JourneyOptions.sorted(Self.timesSquareToConeyIsland, for: .departAt(Self.start)).map(\.id) == ids)
    }

    @Test func aRealSavingStillWinsOverAChange() {
        let options = [
            Self.journey("direct", arrivesIn: 60, rides: [60]),
            Self.journey("transfer", arrivesIn: 45, rides: [20, 25]),
        ]
        // Fifteen minutes saved outweighs the five a change costs.
        #expect(JourneyOptions.sorted(options, for: .now).map(\.id) == ["transfer", "direct"])
        // Four minutes saved doesn't.
        let close = [
            Self.journey("direct", arrivesIn: 60, rides: [60]),
            Self.journey("transfer", arrivesIn: 56, rides: [20, 36]),
        ]
        #expect(JourneyOptions.sorted(close, for: .now).map(\.id) == ["direct", "transfer"])
    }

    @Test func penaltyCountsChangesAndShortRidesButNotTheLastOrTheOnlyRide() {
        let penalty = JourneyOptions.penaltySeconds(for:)
        #expect(penalty(Self.journey("a", arrivesIn: 20, rides: [2])) == 0)
        #expect(penalty(Self.journey("b", arrivesIn: 20, rides: [10, 10])) == 300)
        // A short last ride costs only its change: a sensible short final hop isn't punished twice.
        #expect(penalty(Self.journey("c", arrivesIn: 20, rides: [10, 1])) == 300)
        // A short ride in the middle costs a change on each side and the hop itself; three minutes is still short.
        #expect(penalty(Self.journey("d", arrivesIn: 20, rides: [10, 3, 10])) == 900)
        #expect(penalty(Self.journey("e", arrivesIn: 20, rides: [10, 4, 10])) == 600)
        // Without segments only the changes count.
        #expect(penalty(Self.summary("f", departsIn: 0, arrivesIn: 20, transfers: 2)) == 600)
    }

    @Test func aShortFinalHopKeepsAReasonableRank() {
        let options = [
            Self.journey("direct", arrivesIn: 40, rides: [40]),
            Self.journey("hop", arrivesIn: 33, rides: [30, 1]),
        ]
        // Seven minutes earlier, one change: the hop leads, since its last ride isn't charged as a short ride too.
        #expect(JourneyOptions.sorted(options, for: .now).map(\.id) == ["hop", "direct"])
    }

    @Test func arrivingPenalisesDepartureEarlier() {
        let options = [
            Self.journey("changes", departsIn: 10, arrivesIn: 40, rides: [12, 1, 20]),
            Self.journey("direct", departsIn: 5, arrivesIn: 40, rides: [35]),
        ]
        let ids = JourneyOptions.sorted(options, for: .arriveBy(Self.start.addingTimeInterval(2400))).map(\.id)
        // Leaving at 10 with two changes and a short hop is worth leaving at -5; the direct ride's 5 wins.
        #expect(ids == ["direct", "changes"])
    }

    @Test func equalScoresBreakDeterministically() {
        let a = Self.journey("a", arrivesIn: 30, rides: [30])
        let b = Self.journey("b", arrivesIn: 30, rides: [30])
        #expect(JourneyOptions.sorted([b, a], for: .now).map(\.id) == ["a", "b"])
        #expect(JourneyOptions.sorted([a, b], for: .now).map(\.id) == ["a", "b"])
        // A change that ties a direct ride's penalised time still ranks after it.
        let tied = [
            Self.journey("change", arrivesIn: 25, rides: [10, 15]),
            Self.journey("direct", arrivesIn: 30, rides: [30]),
        ]
        #expect(JourneyOptions.sorted(tied, for: .now).map(\.id) == ["direct", "change"])
        // Nothing is dropped.
        #expect(JourneyOptions.sorted(Self.timesSquareToConeyIsland, for: .now).count == 3)
    }

    @Test func optionsFromAPlan() async throws {
        let transport = try FixtureTransport(fixture: "plan-red-hook-to-times-square")
        let response = try await TransitClient(transport: transport).plan(PlanRequest(
            from: .stop(id: "a"),
            to: .stop(id: "b")
        ))
        let itinerary = try #require(response.itineraries.first)
        let bus = itinerary.legs[1].startTime

        let options = JourneyOptions.options(from: response, for: .now, now: bus.addingTimeInterval(-600))
        #expect(options.map(\.id) == [itinerary.id])
        #expect(options.first?.summary.transfers == 1)
        // A minute after the bus left, the option still shows; two minutes after, it's gone.
        #expect(JourneyOptions.options(from: response, for: .now, now: bus.addingTimeInterval(60)).count == 1)
        #expect(JourneyOptions.options(from: response, for: .now, now: bus.addingTimeInterval(120)).isEmpty)
        // A planned time keeps every option, gone or not.
        #expect(JourneyOptions.options(from: response, for: .departAt(bus), now: bus.addingTimeInterval(3600))
            .count == 1)
    }
}
