import Foundation
import Testing
@testable import TransitKit

struct JourneyPlanTests {
    static func date(_ string: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: string))
    }

    // MARK: - Steps

    @Test func busThenSubwayWithATransfer() throws {
        let plan = try JourneyPlan(FixtureTransport.firstItinerary("plan-red-hook-to-times-square"))

        // Walk, B57, transfer (its walk folded in), A, walk.
        #expect(plan.steps.map(\.legIndices) == [[0], [1], [2], [3], [4]])
        guard case let .walk(first) = plan.steps[0], case .transfer = plan.steps[2],
              case let .walk(last) = plan.steps[4]
        else {
            Issue.record("Unexpected steps: \(plan.steps)")
            return
        }
        #expect(first.to == "LORRAINE ST/COLUMBIA ST")
        #expect(first.distanceMeters == 221)
        #expect(last.from == "42 St-Port Authority Bus Terminal")

        let bus = plan.rides[0]
        #expect(bus.bullet?.text == "B57")
        #expect(bus.mode == .bus)
        #expect(bus.headsign == "MASPETH")
        #expect(bus.direction == nil)
        #expect(bus.board.name == "LORRAINE ST/COLUMBIA ST")
        #expect(bus.alight.name == "JAY ST/FULTON ST")
        #expect(bus.intermediateStops.count == 10)
        #expect(bus.stopCount == 11)
        #expect(bus.formattedStopCount == "11 stops")
        #expect(!bus.isCancelled)
        // Predicted 20:31 against 20:33: two minutes early.
        #expect(bus.board.delayMinutes == -2)
        #expect(bus.board.status() == .early(minutes: 2))
        #expect(bus.board.status(realtimeIsStale: true) == .uncertain)

        let train = plan.rides[1]
        #expect(train.bullet?.text == "A")
        #expect(train.headsign == "Inwood-207 St")
        #expect(train.direction == "Uptown")
        #expect(train.intermediateStops.count == 7)

        let transfer = try #require(plan.transfers.first)
        #expect(transfer.from == "JAY ST/FULTON ST")
        #expect(transfer.to == "Jay St-MetroTech")
        #expect(transfer.changesStation)
        #expect(transfer.walkDistanceMeters == 69)
        #expect(transfer.formattedWalk == "2 min walk")
        // Arrives 20:52, walks 2 minutes, the A leaves 20:56: two minutes to spare.
        #expect(transfer.waitSeconds == 120)
        #expect(transfer.status == .comfortable)
        #expect(transfer.formattedWait == "2 min wait")
        #expect(plan.problem == nil)
    }

    @Test func subwayTransferWithAMinuteToSpareIsTight() throws {
        let plan = try JourneyPlan(FixtureTransport.firstItinerary("plan-union-square-to-williamsburg"))
        let transfer = try #require(plan.transfers.first)
        // The W reaches Prince St at 20:34, the walk to Broadway-Lafayette takes 4 minutes, the M leaves at 20:39.
        #expect(transfer.waitSeconds == 60)
        #expect(transfer.status == .tight)
        #expect(transfer.formattedWait == "1 min wait")
        #expect(plan.rides.map(\.direction) == ["Downtown", "Downtown & Brooklyn"])
        #expect(plan.problem == nil)
    }

    @Test func transferMissedOnLiveTimes() throws {
        var itinerary = try FixtureTransport.firstItinerary("plan-red-hook-to-times-square")
        // The B57 running four minutes late reaches Jay St at 20:56, as the A leaves.
        itinerary.legs[1].endTime += 4 * 60
        let plan = JourneyPlan(itinerary)
        let transfer = try #require(plan.transfers.first)
        #expect(transfer.waitSeconds == -120)
        #expect(transfer.status == .missed)
        #expect(transfer.formattedWait == "Missed by 2 min")
        #expect(plan.problem == .missedTransfer(transfer))
        #expect(plan.problem?.message == "The connection at Jay St-MetroTech is missed by 2 min on live times.")
    }

    @Test func noWaitUnderHalfAMinute() throws {
        var itinerary = try FixtureTransport.firstItinerary("plan-red-hook-to-times-square")
        itinerary.legs[3].startTime = itinerary.legs[1].endTime
            .addingTimeInterval(TimeInterval(itinerary.legs[2].duration))
        let transfer = try #require(JourneyPlan(itinerary).transfers.first)
        #expect(transfer.waitSeconds == 0)
        #expect(transfer.status == .tight)
        #expect(transfer.formattedWait == "No wait")
    }

    @Test func cancelledRideMakesTheJourneyImpossible() throws {
        var itinerary = try FixtureTransport.firstItinerary("plan-red-hook-to-times-square")
        itinerary.legs[3].cancelled = true
        let plan = JourneyPlan(itinerary)
        #expect(plan.rides[1].isCancelled)
        #expect(plan.problem == .cancelled(plan.rides[1]))
        #expect(plan.problem?.message == "The A to Inwood-207 St is cancelled.")
    }

    @Test func skippedStopCancelsTheRide() throws {
        var itinerary = try FixtureTransport.firstItinerary("plan-red-hook-to-times-square")
        itinerary.legs[1].to.cancelled = true
        let plan = JourneyPlan(itinerary)
        #expect(plan.rides[0].alight.isCancelled)
        #expect(plan.rides[0].alight.status() == .cancelled)
        #expect(plan.problem?.message == "The B57 no longer stops at JAY ST/FULTON ST.")

        // A cancellation outranks a missed transfer.
        itinerary.legs[1].endTime += 10 * 60
        #expect(JourneyPlan(itinerary).problem == .cancelled(JourneyPlan(itinerary).rides[0]))
    }

    @Test func boardingRefusedCancelsTheRide() throws {
        var itinerary = try FixtureTransport.firstItinerary("plan-red-hook-to-times-square")
        itinerary.legs[3].from.pickupType = .notAllowed
        let plan = JourneyPlan(itinerary)
        #expect(plan.problem?.message == "The A no longer stops at Jay St-MetroTech.")
    }

    @Test func stayingAboardIsNoTransfer() throws {
        var itinerary = try FixtureTransport.firstItinerary("plan-red-hook-to-times-square")
        itinerary.legs.remove(at: 2)
        itinerary.legs[2].interlineWithPreviousLeg = true
        let plan = JourneyPlan(itinerary)
        #expect(plan.transfers.isEmpty)
        #expect(plan.rides.count == 2)
        #expect(plan.rides[1].staysAboard)
    }

    @Test func walkOnlyJourney() throws {
        var itinerary = try FixtureTransport.firstItinerary("plan-red-hook-to-times-square")
        itinerary.legs = [itinerary.legs[0]]
        let plan = JourneyPlan(itinerary)
        #expect(plan.steps.count == 1)
        #expect(plan.rides.isEmpty)
        #expect(plan.problem == nil)
    }

    @Test func platformTrackWhereTheFeedGivesOne() throws {
        var itinerary = try FixtureTransport.firstItinerary("plan-red-hook-to-times-square")
        #expect(JourneyPlan(itinerary).rides[1].board.track == nil)
        itinerary.legs[3].from.scheduledTrack = "2"
        #expect(JourneyPlan(itinerary).rides[1].board.track == "2")
        itinerary.legs[3].from.track = "4"
        #expect(JourneyPlan(itinerary).rides[1].board.track == "4")
    }

    // MARK: - Walks

    @Test func walkStepsFoldIntoTurns() throws {
        let itinerary = try FixtureTransport.firstItinerary("plan-red-hook-to-times-square")
        // Eleven unnamed path segments read as one instruction covering them all.
        let first = WalkInstruction.instructions(from: itinerary.legs[0].steps ?? [])
        #expect(first.map(\.text) == ["Start walking"])
        #expect(first.first?.distanceMeters == 221)
        #expect(first.first?.formattedDistance == "0.1 mi")

        let last = itinerary.legs[4].steps ?? []
        let instructions = WalkInstruction.instructions(from: last)
        #expect(!instructions.isEmpty)
        #expect(instructions.count <= last.count)
        #expect(instructions.map(\.distanceMeters).reduce(0, +) == last.map(\.distance).reduce(0, +))
    }

    @Test func walkInstructionWording() throws {
        let decoder = JSONDecoder()
        let steps = try decoder.decode([StepInstruction].self, from: Data("""
        [
          \(Self.step("DEPART", "Union Square East", 40)),
          \(Self.step("CONTINUE", "Union Square East", 60)),
          \(Self.step("LEFT", "East 14th Street", 120)),
          \(Self.step("CONTINUE", "", 10)),
          \(Self.step("SLIGHTLY_RIGHT", "", 30)),
          \(Self.step("STAIRS", "", 8)),
          \(Self.step("CONTINUE", "Broadway", 900))
        ]
        """.utf8))
        let instructions = WalkInstruction.instructions(from: steps)
        #expect(instructions.map(\.text) == [
            "Walk along Union Square East",
            "Turn left onto East 14th Street",
            "Bear right",
            "Take the stairs",
            "Continue on Broadway",
        ])
        #expect(instructions.map(\.distanceMeters) == [100, 130, 30, 8, 900])
    }

    private static func step(_ direction: String, _ street: String, _ distance: Double) -> String {
        """
        {"relativeDirection": "\(direction)", "distance": \(distance), "fromLevel": 0, "toLevel": 0,
         "polyline": {"points": "", "precision": 6, "length": 0}, "streetName": "\(street)", "exit": "",
         "stayOn": false, "area": false}
        """
    }

    // MARK: - Formatting

    @Test func distances() {
        #expect(DistanceFormat.string(meters: 0) == "10 ft")
        #expect(DistanceFormat.string(meters: 69) == "230 ft")
        #expect(DistanceFormat.string(meters: 160) == "520 ft")
        #expect(DistanceFormat.string(meters: 170) == "0.1 mi")
        #expect(DistanceFormat.string(meters: 2050) == "1.3 mi")
    }

    @Test func subwayDirections() {
        #expect(SubwayDirection.label(line: "6", stopId: "us-ny-MTA-NYCSubway_635N") == "Uptown & The Bronx")
        #expect(SubwayDirection.label(line: "6X", stopId: "us-ny-MTA-NYCSubway_635S") == "Downtown")
        #expect(SubwayDirection.label(line: "L", stopId: "us-ny-MTA-NYCSubway_L03S") == "Brooklyn")
        // Shuttles, buses, and stations rather than platforms have none.
        #expect(SubwayDirection.label(line: "S", stopId: "us-ny-MTA-NYCSubway_902N") == nil)
        #expect(SubwayDirection.label(line: "M101", stopId: "us-ny-MTA-BusManhattan_401234") == nil)
        #expect(SubwayDirection.label(line: "6", stopId: "us-ny-MTA-NYCSubway_635") == nil)
    }

    @Test func rideDuration() throws {
        let plan = try JourneyPlan(FixtureTransport.firstItinerary("plan-red-hook-to-times-square"))
        #expect(plan.rides[0].formattedDuration == "21 min")
    }
}
