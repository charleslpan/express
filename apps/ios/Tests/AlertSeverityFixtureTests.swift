import Foundation
import Testing
import TransitKit
@testable import Express

/// `nyc-alerts-mixed` (A5): a neutral "Express to Local" next to a red suspension, on Nearby and on a journey's legs,
/// coloured by the MTA's type MOTIS passes on as `effectDetail`, as line status colours it.
@MainActor
struct AlertSeverityFixtureTests {
    private static let fixtures = FixtureSet.nycAlertsMixed

    @Test func nearbyShowsTheLocalQAsANoticeBesideTheSuspendedL() async throws {
        let response = try await Self.fixtures.transitClient
            .departures(DeparturesRequest(stopId: "us-ny-MTA-NYCSubway_635"))
        func levels(_ route: String, direction: String) -> [AlertLevel] {
            response.stopTimes
                .filter { $0.routeId == "us-ny-MTA-NYCSubway_\(route)" && $0.directionId == direction }
                .flatMap(\.serviceAlerts)
                .active(at: Self.fixtures.referenceDate)
                .map(\.level)
        }
        #expect(levels("Q", direction: "0") == [.info])
        #expect(levels("Q", direction: "1").isEmpty)
        #expect(levels("L", direction: "0") == [.severe])
        #expect(levels("4", direction: "0") == [.warning])
    }

    @Test func theJourneyShowsTheLocalQBesideTheSuspendedShuttle() throws {
        let journey = try #require(FixtureSet.journey(id: "fixture-q-s", fixtures: Self.fixtures))
        let qRide = try #require(journey.legs.first { $0.tripId == "fixture-trip-q" })
        let shuttle = try #require(journey.legs.first { $0.tripId == "fixture-trip-s" })
        #expect(qRide.applicableAlerts.map(\.type) == ["Planned - Express to Local"])
        #expect(qRide.applicableAlerts.map(\.level) == [.info])
        #expect(qRide.skippedStops.isEmpty, "running local skips no stop")
        #expect(shuttle.applicableAlerts.map(\.level) == [.severe])
        // The option's flag is the suspension's: red, on the shuttle alone.
        let flag = try #require(journey.alertFlag)
        #expect(flag.level == .severe)
        #expect(flag.lines.map(\.bullet.text) == ["S"])
    }

    @Test func nycAlertsKeepsItsColours() throws {
        let lThenBus = try #require(FixtureSet.journey(id: "fixture-l-m101", fixtures: .nycAlerts))
        let ride = try #require(lThenBus.legs.first { $0.tripId == "fixture-trip-l" })
        #expect(ride.skippedStops.map(\.alert.type) == ["Stops Skipped"])
        let qRide = try #require(FixtureSet.journey(id: "fixture-q-s", fixtures: .nycAlerts)?.legs
            .first { $0.tripId == "fixture-trip-q" })
        #expect(qRide.applicableAlerts.isEmpty, "the local Q is nyc-alerts-mixed's alone")
    }
}
