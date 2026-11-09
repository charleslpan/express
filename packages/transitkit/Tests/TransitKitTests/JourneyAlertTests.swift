import Foundation
import Testing
@testable import TransitKit

/// Alerts on a journey's legs: Union Square to Williamsburg, a walk, the W 20:30–20:34, a walk, the M 20:39–20:50
/// (UTC), and a walk.
struct JourneyAlertTests {
    static func itinerary() throws -> Itinerary {
        try FixtureTransport.firstItinerary("plan-union-square-to-williamsburg")
    }

    static func date(_ time: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: "2026-11-03T\(time):00Z"))
    }

    static func alert(
        _ header: String,
        effect: Components.Schemas.AlertEffect = .noService,
        from start: String,
        to end: String,
        severity: Components.Schemas.AlertSeverityLevel? = nil
    ) throws -> Components.Schemas.Alert {
        try Components.Schemas.Alert(
            communicationPeriod: [.init(start: date(start), end: date(end))],
            cause: .unknownCause,
            effect: effect,
            headerText: header,
            descriptionText: "",
            severityLevel: severity
        )
    }

    // MARK: - The leg's window

    @Test func alertsApplyOnlyWhileTheRiderIsOnTheLeg() throws {
        var itinerary = try Self.itinerary()
        let delays = try Self.alert("[M] trains are delayed", effect: .significantDelays, from: "20:00", to: "21:00")
        let tomorrow = try Self.alert("No [M] trains overnight", from: "23:45", to: "23:59")
        let earlier = try Self.alert("No [M] trains earlier", from: "19:00", to: "20:39")
        itinerary.legs[3].alerts = [delays, tomorrow, earlier]

        #expect(itinerary.legs[3].serviceAlerts.count == 3)
        // The night work and the suspension that ended the minute the M leaves are in the feed, but don't show.
        #expect(itinerary.legs[3].applicableAlerts.map(\.header) == ["[M] trains are delayed"])
    }

    @Test func aLegThatCrossesAnAlertBoundary() throws {
        var itinerary = try Self.itinerary()
        // Starts mid-ride on the M (20:39–20:50), after the W (20:30–20:34) has arrived.
        let suspension = try Self.alert("No [M] or [W] trains", from: "20:45", to: "23:00")
        itinerary.legs[1].alerts = [suspension]
        itinerary.legs[3].alerts = [suspension]

        #expect(itinerary.legs[1].applicableAlerts.isEmpty)
        #expect(itinerary.legs[3].applicableAlerts.map(\.header) == ["No [M] or [W] trains"])
    }

    @Test func theWindowRunsFromTheEarlierDepartureToTheLaterArrival() throws {
        var leg = try Self.itinerary().legs[3]
        leg.startTime = try Self.date("20:42")
        leg.endTime = try Self.date("20:53")
        #expect(try leg.alertWindow == DateInterval(start: Self.date("20:39"), end: Self.date("20:53")))
        // Running late, the M is still on the line when work that starts at 20:51 begins.
        leg.alerts = try [Self.alert("No [M] trains", from: "20:51", to: "22:00")]
        #expect(leg.applicableAlerts.count == 1)
    }

    // MARK: - Deduping and ordering

    @Test func dedupedAndMostSevereFirst() throws {
        var itinerary = try Self.itinerary()
        let notice = try Self.alert("Elevator out of service", effect: .otherEffect, from: "20:00", to: "21:00")
        let delays = try Self.alert("[M] trains are delayed", effect: .significantDelays, from: "20:00", to: "21:00")
        let suspension = try Self.alert("No [M] trains to Manhattan", from: "20:00", to: "21:00")
        itinerary.legs[3].alerts = [notice, delays, suspension, delays]
        // The same alert on the line and its boarding stop shows once.
        itinerary.legs[3].from.alerts = [suspension]

        #expect(itinerary.legs[3].applicableAlerts.map(\.header) == [
            "No [M] trains to Manhattan", "[M] trains are delayed", "Elevator out of service",
        ])
    }

    @Test func aWalkLeavesItsStopsAlertsToTheRide() throws {
        var itinerary = try Self.itinerary()
        let elevator = try Self.alert("Elevator out of service", effect: .otherEffect, from: "20:00", to: "21:00")
        // Leg 2 walks to Broadway-Lafayette St, where the M (leg 3) boards.
        itinerary.legs[2].to.alerts = [elevator]
        itinerary.legs[3].from.alerts = [elevator]

        #expect(itinerary.legs[2].applicableAlerts.isEmpty)
        #expect(itinerary.legs[3].applicableAlerts.map(\.header) == ["Elevator out of service"])
    }

    // MARK: - Skipped stops

    @Test func detectsSkippedBoardingAndAlightingStops() throws {
        var leg = try Self.itinerary().legs[3]
        leg.from.alerts = try [Self.alert(
            "[M] trains skip Broadway-Lafayette St",
            effect: .modifiedService,
            from: "20:00",
            to: "21:00"
        )]
        leg.to.alerts = try [Self.alert("Marcy Av is closed", from: "20:00", to: "21:00")]

        let skipped = leg.skippedStops
        #expect(skipped.map(\.role) == [.board, .alight])
        #expect(skipped.map(\.name) == ["Broadway-Lafayette St", "Marcy Av"])
        #expect(skipped.first?.alert.header == "[M] trains skip Broadway-Lafayette St")
    }

    @Test func otherStopAlertsAreNotSkippedStops() throws {
        var leg = try Self.itinerary().legs[3]
        leg.from.alerts = try [
            Self.alert("Elevator out of service", effect: .otherEffect, from: "20:00", to: "21:00"),
            Self.alert("Express to local", effect: .modifiedService, from: "20:00", to: "21:00", severity: .info),
            Self.alert("[M] trains are delayed", effect: .significantDelays, from: "20:00", to: "21:00"),
        ]
        #expect(leg.skippedStops.isEmpty)
        // They still show as banners.
        #expect(leg.applicableAlerts.count == 3)
    }

    @Test func aLineWideSuspensionIsNotASkippedStop() throws {
        var leg = try Self.itinerary().legs[3]
        let suspension = try Self.alert("No [M] trains", from: "20:00", to: "21:00")
        leg.alerts = [suspension]
        leg.from.alerts = [suspension]
        #expect(leg.skippedStops.isEmpty)
    }

    @Test func aSkippedStopOutsideTheLegsWindowDoesNotShow() throws {
        var leg = try Self.itinerary().legs[3]
        leg.from.alerts = try [Self.alert(
            "[M] trains skip Broadway-Lafayette St",
            effect: .modifiedService,
            from: "22:00",
            to: "23:00"
        )]
        #expect(leg.skippedStops.isEmpty)
        #expect(leg.applicableAlerts.isEmpty)
    }

    @Test func aWalkSkipsNoStops() throws {
        var walk = try Self.itinerary().legs[2]
        walk.to.alerts = try [Self.alert("Station closed", from: "20:00", to: "21:00")]
        #expect(walk.skippedStops.isEmpty)
    }

    // MARK: - The option's flag

    @Test func noFlagWithoutApplicableAlerts() throws {
        var itinerary = try Self.itinerary()
        #expect(itinerary.alertFlag == nil)
        itinerary.legs[3].alerts = try [Self.alert("No [M] trains overnight", from: "23:45", to: "23:59")]
        #expect(itinerary.alertFlag == nil)
    }

    @Test func theFlagTakesTheMostSevereLevelAndItsLines() throws {
        var itinerary = try Self.itinerary()
        itinerary.legs[1].alerts = try [Self.alert(
            "[W] delays",
            effect: .significantDelays,
            from: "20:00",
            to: "21:00"
        )]
        itinerary.legs[3].alerts = try [Self.alert("No [M] trains", from: "20:00", to: "21:00")]

        let flag = try #require(itinerary.alertFlag)
        #expect(flag.level == .severe)
        #expect(flag.lines.map(\.bullet.text) == ["M"])
        #expect(flag.lines.first?.mode == .subway)
        #expect(flag.mayAffectJourney)
    }

    @Test func anAmberFlagNamesEveryLineAtItsLevel() throws {
        var itinerary = try Self.itinerary()
        let delays = try Self.alert("Delays", effect: .significantDelays, from: "20:00", to: "21:00")
        itinerary.legs[1].alerts = [delays]
        itinerary.legs[3].alerts = [delays]

        let flag = try #require(itinerary.alertFlag)
        #expect(flag.level == .warning)
        #expect(flag.lines.map(\.bullet.text) == ["W", "M"])
        #expect(!flag.mayAffectJourney)
    }

    @Test func aSkippedBoardingStopFlagsTheOption() throws {
        var itinerary = try Self.itinerary()
        itinerary.legs[1].from.alerts = try [Self.alert(
            "[W] trains skip 14 St-Union Sq",
            effect: .modifiedService,
            from: "20:00",
            to: "21:00"
        )]
        let flag = try #require(itinerary.alertFlag)
        #expect(flag.level == .severe)
        #expect(flag.lines.map(\.bullet.text) == ["W"])
    }
}
