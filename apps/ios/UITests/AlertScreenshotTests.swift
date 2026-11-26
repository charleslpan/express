import XCTest

extension ScreenshotTests {
    // Service alerts (A3): banners on Nearby's rows (a red L and an amber uptown 4, and no banner for the 6's work two
    // weeks away; with A5's `nyc-alerts-mixed`, a neutral uptown 6 running local too), an alert's full
    // text, and a stop's alerts. They sit in a
    // file of their own so `ScreenshotTests.swift` stays within SwiftLint's length; `@objc` keeps them visible to
    // XCTest, which finds tests through the Objective-C runtime.

    @objc func testAlertsNearby() {
        capture("alerts-nearby", fixtures: "nyc-alerts", settledWhen: "nearby.loaded", "nearby.alert")
    }

    /// A5: Pelham Bay Park-bound 6s running local, a neutral notice, between the L's red suspensions.
    @objc func testAlertsNearbyMixed() {
        capture("alerts-nearby", fixtures: "nyc-alerts-mixed", settledWhen: "nearby.loaded", "nearby.alert")
    }

    @objc func testAlertDetail() {
        capture("alert-detail", fixtures: "nyc-alerts", settledWhen: "nearby.alert") { app in
            app.descendants(matching: .any).matching(identifier: "nearby.alert").firstMatch.tap()
            let opened = app.descendants(matching: .any)["alerts.detail"].waitForExistence(timeout: 10)
            XCTAssertTrue(opened, "The alert's full text never opened")
        }
    }

    @objc func testStopAlerts() {
        capture("stop-alerts", fixtures: "nyc-alerts", settledWhen: "stop.loaded", "stop.alerts")
    }
}
