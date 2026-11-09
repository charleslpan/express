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

    // Alerts on journeys (A4): the options with a red and an amber flag, the shuttle's suspension on its ride, the L
    // skipping the boarding stop, and the 6, whose alerts in the feed fall outside the ride and show nothing.
    // `@objc`, as in `AlertScreenshotTests.swift`, keeps them visible to XCTest.

    @objc func testJourneysAlerts() {
        capture("journeys-alerts", fixtures: "nyc-alerts", settledWhen: "journeys.list")
    }

    @objc func testJourneyAlertSuspension() {
        capture("journey-alert-suspension", fixtures: "nyc-alerts", settledWhen: "journey.loaded", "journey.alert")
    }

    /// A5: the Q running local, a neutral notice, on the ride before the shuttle's red suspension.
    @objc func testJourneyAlertSuspensionMixed() {
        capture(
            "journey-alert-suspension",
            fixtures: "nyc-alerts-mixed",
            settledWhen: "journey.loaded",
            "journey.alert"
        )
    }

    @objc func testJourneyAlertSkipped() {
        capture(
            "journey-alert-skipped",
            fixtures: "nyc-alerts",
            settledWhen: "journey.loaded",
            "journey.stop-skipped"
        )
    }

    @objc func testJourneyAlertOutside() {
        capture("journey-alert-outside", fixtures: "nyc-alerts", settledWhen: "journey.loaded") { app in
            let banner = app.descendants(matching: .any)["journey.alert"]
            XCTAssertFalse(banner.exists, "An alert outside the ride's time showed")
        }
    }
}
