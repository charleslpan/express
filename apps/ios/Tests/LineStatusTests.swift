import Foundation
import Testing
import TransitKit
@testable import Express

@MainActor
struct LineStatusTests {
    private let now = FixtureSet.nycAlerts.referenceDate

    private func alert(_ id: String, effect: String, from start: TimeInterval, to end: TimeInterval?) -> ServiceAlert {
        ServiceAlert(
            id: id,
            effect: effect,
            isPlanned: start > 0,
            activePeriods: [AlertPeriod(start: now.addingTimeInterval(start), end: end.map(now.addingTimeInterval))],
            header: id,
            description: nil
        )
    }

    @Test func groupsLinesByTheirWorstCurrentAlert() {
        let response = LineStatusResponse(lines: [
            "L": [alert("l-suspended", effect: "NO_SERVICE", from: -600, to: nil)],
            "4": [
                alert("4-notice", effect: "STOP_MOVED", from: -600, to: nil),
                alert("4-delays", effect: "SIGNIFICANT_DELAYS", from: -600, to: 600),
            ],
            "6": [alert("6-nights", effect: "NO_SERVICE", from: 14 * 86400, to: 14 * 86400 + 18000)],
            "6X": [alert("6-nights", effect: "NO_SERVICE", from: 14 * 86400, to: 14 * 86400 + 18000)],
        ])
        let sections = LineStatusSections(lines: LineStatusLine.subway, response: response, now: now)
        #expect(sections.groups.map(\.level) == [.severe, .warning])
        #expect(sections.groups[0].rows.map(\.line.id) == ["L"])
        #expect(sections.groups[1].rows.map(\.line.id) == ["4"])
        #expect(sections.groups[1].rows[0].alerts.map(\.id) == ["4-delays", "4-notice"])
        // Work two weeks away is upcoming, once, and leaves its line in good service now.
        #expect(sections.upcoming.map(\.alert.id) == ["6-nights"])
        #expect(sections.upcoming[0].lines.map(\.id) == ["6"])
        #expect(sections.goodService.contains { $0.id == "6" })
        #expect(sections.goodService.count == LineStatusLine.subway.count - 2)
        #expect(!sections.isAllGood)
    }

    @Test func allGoodWithoutCurrentAlerts() {
        let empty = LineStatusResponse(lines: [:])
        let sections = LineStatusSections(lines: LineStatusLine.subway, response: empty, now: now)
        #expect(sections.isAllGood)
        #expect(sections.goodService.count == LineStatusLine.subway.count)
    }

    @Test func fixtureSetAnswersLineStatus() async throws {
        let response = try await FixtureSet.nycAlerts.transitClient.lineStatus(lines: ["L", "4", "6", "M14D+"])
        let sections = LineStatusSections(
            lines: LineStatusLine.subway.filter { ["L", "4", "6"].contains($0.id) },
            response: response,
            now: now
        )
        // The recorded feed has the 4 skipping Burnside Av for planned work then too, so it's with the L.
        #expect(sections.groups.first?.level == .severe)
        #expect(sections.groups.first?.rows.map(\.line.id) == ["4", "L"])
        #expect(sections.upcoming.contains { $0.alert.id == "fixture:planned_work:6-nights" })
        let quiet = try await FixtureSet.nycEvening.transitClient.lineStatus(lines: ["L", "4"])
        #expect(quiet.lines["L"] == [])
    }
}
