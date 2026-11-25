import Foundation
import Testing
import TransitKit
@testable import Express

@MainActor
struct JourneyDetailModelTests {
    private static let now = FixtureSet.nycEvening.referenceDate

    private func journey(_ id: String) throws -> Itinerary {
        try #require(FixtureSet.journey(id: id))
    }

    @Test func refreshKeepsTheJourneyLive() async throws {
        let model = try JourneyDetailModel(itinerary: journey("fixture-6"))
        #expect(!model.hasRefreshed)
        #expect(!model.mayNotBeRealTime(at: Self.now))

        await model.refresh(client: FixtureSet.nycEvening.transitClient) { Self.now }
        #expect(model.hasRefreshed)
        #expect(model.refreshedAt == Self.now)
        #expect(model.plan.problem == nil)
        #expect(model.plan.rides.first?.intermediateStops.map(\.name) == ["23 St-Baruch College", "28 St", "33 St"])
        #expect(model.plan.rides.first?.board.status() == .late(minutes: 2))
        #expect(!model.mayNotBeRealTime(at: Self.now))
        // A minute and more without a refresh, and the times may not be real time.
        #expect(model.mayNotBeRealTime(at: Self.now.addingTimeInterval(61)))
    }

    @Test func cancelledTrainMakesTheJourneyImpossible() async throws {
        let model = try JourneyDetailModel(itinerary: journey("fixture-6"))
        await model.refresh(client: FixtureSet.nycEveningCancelled.transitClient) { Self.now }
        #expect(model.plan.rides.first?.isCancelled == true)
        #expect(model.plan.problem?.message == "The 6 to Pelham Bay Park is cancelled.")
    }

    @Test func staleRealtimeData() async throws {
        let model = try JourneyDetailModel(itinerary: journey("fixture-6"))
        await model.refresh(client: FixtureSet.nycEveningStale.transitClient) { Self.now }
        #expect(model.mayNotBeRealTime(at: Self.now))
    }

    @Test func failedRefreshKeepsTheTimesShown() async throws {
        let itinerary = try journey("fixture-q-s")
        let model = JourneyDetailModel(itinerary: itinerary)
        await model.refresh(client: FixtureSet.offline.transitClient) { Self.now }
        #expect(model.hasRefreshed)
        #expect(model.refreshedAt == nil)
        #expect(model.itinerary == itinerary)
    }

    @Test func tightTransferInTheFixtures() throws {
        let plan = try JourneyPlan(journey("fixture-q-s"))
        #expect(plan.transfers.map(\.status) == [.tight])
        #expect(plan.transfers.first?.formattedWait == "1 min wait")
        let bus = try JourneyPlan(journey("fixture-l-m101"))
        #expect(bus.transfers.map(\.status) == [.comfortable])
        #expect(bus.rides.map(\.mode) == [.subway, .bus])
    }

    @Test func offersTheRoutesNextDeparturesAndFindsMore() async throws {
        let model = try JourneyDetailModel(
            itinerary: journey("fixture-6"),
            alternatives: [journey("fixture-6-b")],
            findsMoreDepartures: true
        )
        func trips() -> [String?] {
            model.departures.map { JourneySummary($0).tripIDs.first }
        }
        #expect(trips() == ["fixture-trip-6", "fixture-trip-6-b"])

        // The two more come from the boarding stop's departures, each checked against its trip.
        await model.findMoreDepartures(client: FixtureSet.nycEvening.transitClient)
        #expect(trips() == ["fixture-trip-6", "fixture-trip-6-b", "fixture-trip-6-c", "fixture-trip-6-d"])
        #expect(model.upcomingDepartures(at: Self.now).count == 4)

        model.select(model.departures[2].id)
        #expect(model.plan.rides.first?.tripId == "fixture-trip-6-c")
        #expect(model.plan.summary.transfers == 0)
        // Refreshing keeps the departure picked, and the others in the strip.
        await model.refresh(client: FixtureSet.nycEvening.transitClient) { Self.now }
        #expect(model.plan.rides.first?.tripId == "fixture-trip-6-c")
        #expect(model.departures.count == 4)
    }

    @Test func departedDeparturesDropOutExceptTheOneOpen() throws {
        let model = try JourneyDetailModel(itinerary: journey("fixture-6"), alternatives: [journey("fixture-6-b")])
        // The first leaves at 6:38 PM and the next at 6:46; the options list's minute of grace applies.
        let sixThirtyNine = Self.now.addingTimeInterval(9 * 60)
        let sixFortyFour = Self.now.addingTimeInterval(14 * 60)
        #expect(model.upcomingDepartures(at: sixThirtyNine).count == 2)
        // The first has gone, but it's the one open, so it stays.
        #expect(model.upcomingDepartures(at: sixFortyFour).count == 2)
        model.select(model.departures[1].id)
        #expect(model.upcomingDepartures(at: sixFortyFour).map(\.id) == [model.itinerary.id])
    }

    @Test func aJourneyWithChangesFindsNoMoreDepartures() async throws {
        let model = try JourneyDetailModel(itinerary: journey("fixture-l-m101"), findsMoreDepartures: true)
        await model.findMoreDepartures(client: FixtureSet.nycEvening.transitClient)
        #expect(model.departures.count == 1)
    }

    @Test func noMoreDeparturesWhenNotAsked() async throws {
        let model = try JourneyDetailModel(itinerary: journey("fixture-6"))
        await model.findMoreDepartures(client: FixtureSet.nycEvening.transitClient)
        #expect(model.departures.count == 1)
    }
}
