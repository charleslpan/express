import Foundation
import Testing
import TransitKit
@testable import Express

/// The `nyc-alerts` journeys the screenshot harness shows (A4): the flags and banners each should carry, before and
/// after journey detail refreshes its rides from their trips.
@MainActor
struct JourneyAlertFixtureTests {
    private static let now = FixtureSet.nycAlerts.referenceDate

    private func journey(_ id: String) throws -> Itinerary {
        try #require(FixtureSet.journey(id: id, fixtures: .nycAlerts))
    }

    @Test func theOptionsHaveARedAndAnAmberFlag() throws {
        let shuttle = try #require(journey("fixture-q-s").alertFlag)
        #expect(shuttle.level == .severe)
        #expect(shuttle.lines.map(\.bullet.text) == ["S"])
        #expect(shuttle.mayAffectJourney)

        let four = try #require(journey("fixture-4").alertFlag)
        #expect(four.level == .warning)
        #expect(four.lines.map(\.bullet.text) == ["4"])
    }

    @Test func alertsOutsideTheRideNeverShow() throws {
        let six = try journey("fixture-6")
        #expect(!six.legs.flatMap(\.serviceAlerts).isEmpty)
        #expect(six.alertFlag == nil)
        let applicable = six.legs.flatMap(\.applicableAlerts)
        #expect(applicable.isEmpty)
    }

    @Test func noAlertsOutsideTheAlertsSet() throws {
        let shuttle = try #require(FixtureSet.journey(id: "fixture-q-s"))
        #expect(shuttle.alertFlag == nil)
    }

    @Test func refreshKeepsTheSuspensionAndTheSkippedStop() async throws {
        let shuttle = try JourneyDetailModel(itinerary: journey("fixture-q-s"))
        await shuttle.refresh(client: FixtureSet.nycAlerts.transitClient) { Self.now }
        let suspended = try #require(shuttle.itinerary.legs.first { $0.tripId == "fixture-trip-s" })
        #expect(suspended.applicableAlerts.map(\.level) == [.severe])

        let lThenBus = try JourneyDetailModel(itinerary: journey("fixture-l-m101"))
        await lThenBus.refresh(client: FixtureSet.nycAlerts.transitClient) { Self.now }
        let ride = try #require(lThenBus.itinerary.legs.first { $0.tripId == "fixture-trip-l" })
        let skipped = try #require(ride.skippedStops.first)
        #expect(ride.skippedStops.count == 1)
        #expect(skipped.role == .board)
        #expect(skipped.name == "14 St-Union Sq")
        #expect(JourneyAlertText.skipped(skipped, mode: ride.mode) == "Trains skip 14 St-Union Sq")
    }

    @Test func theFlagSaysTheJourneyMayBeAffected() throws {
        let flag = try #require(journey("fixture-q-s").alertFlag)
        #expect(JourneyAlertText.flag(flag).hasPrefix("Alert on the S train."))
        #expect(JourneyAlertText.flag(flag).contains("may be affected"))
        let four = try #require(journey("fixture-4").alertFlag)
        #expect(JourneyAlertText.flag(four) == "Delays or changes on the 4 train")
    }
}
