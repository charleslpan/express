import XCTest

/// Journey detail (J2), in its own file to keep `ScreenshotTests.swift` short.
extension ScreenshotTests {
    // Journey detail (J2), pushed over the options: the 6 running late, the L and the M101 with a transfer, the Q and
    // the shuttle with a tight transfer, the 6 cancelled, times that may not be real time, and the stops between
    // unfolded.

    func testJourneySubway() {
        capture("journey-subway", fixtures: "nyc-evening", settledWhen: "journey.loaded")
    }

    func testJourneyBus() {
        capture("journey-bus", fixtures: "nyc-evening", settledWhen: "journey.loaded")
    }

    func testJourneyTight() {
        capture("journey-tight", fixtures: "nyc-evening", settledWhen: "journey.transfer-tight")
    }

    func testJourneyCancelled() {
        capture("journey-cancelled", fixtures: "nyc-evening-cancelled", settledWhen: "journey.problem")
    }

    func testJourneyStale() {
        capture("journey-stale", fixtures: "nyc-evening-stale", settledWhen: "journey.may-not-be-real-time")
    }

    func testJourneyStops() {
        capture("journey-stops", fixtures: "nyc-evening", settledWhen: "journey.loaded")
    }
}
