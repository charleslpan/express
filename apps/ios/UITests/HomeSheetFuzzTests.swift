import XCTest

/// Exploratory: arbitrary drags over the real app's home sheet, logging whether its content ever moves sideways.
@MainActor
final class HomeSheetFuzzTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = true
    }

    func testRealLaunchDark() { run(arguments: ["-AppleInterfaceStyle", "Dark"], raise: true) }
    func testRealLaunchLightAX5() {
        run(arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"], raise: true)
    }
    func testHarnessHalfDark() {
        run(arguments: ["-screenshot", "home-half", "-fixtures", "nyc-evening", "-appearance", "dark"], raise: false)
    }

    private func log(_ s: String) { XCTContext.runActivity(named: s) { _ in } }

    private func run(arguments: [String], raise: Bool) {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        let search = app.descendants(matching: .any)["home.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 30))
        let window = app.windows.firstMatch
        sleep(3)
        if raise {
            let grabber = app.buttons["Sheet Grabber"]
            if grabber.waitForExistence(timeout: 10) {
                let from = grabber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                let to = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
                from.press(forDuration: 0.1, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.5)
                sleep(2)
            }
        }
        let base = search.frame
        log("base search \(base) window \(window.frame)")
        var index = 0
        let starts: [(Double, Double)] = [(0.5, 0.5), (0.25, 0.55), (0.75, 0.6), (0.5, 0.7), (0.15, 0.8), (0.85, 0.85), (0.5, 0.95), (0.5, 0.42)]
        let deltas: [(Double, Double)] = [(0.6, 0), (-0.6, 0), (0.5, 0.15), (-0.5, -0.15), (0.3, -0.3), (-0.3, 0.3), (0.0, 0.4), (0.7, 0.05)]
        for (sx, sy) in starts {
            for (dx, dy) in deltas {
                index += 1
                if !search.exists {
                    let cancel = app.buttons["Cancel"]
                    if cancel.exists { cancel.tap() } else { log("search gone; stopping at \(index)"); return }
                    sleep(1)
                }
                let ex = min(max(sx + dx, 0.02), 0.98), ey = min(max(sy + dy, 0.2), 0.98)
                let from = window.coordinate(withNormalizedOffset: CGVector(dx: sx, dy: sy))
                let to = window.coordinate(withNormalizedOffset: CGVector(dx: ex, dy: ey))
                let long = index % 3 == 0
                from.press(forDuration: long ? 0.8 : 0.05, thenDragTo: to, withVelocity: index % 2 == 0 ? .slow : .default, thenHoldForDuration: 0.4)
                let state: String
                if search.exists {
                    let f = search.frame
                    let moved = abs(f.minX - base.minX) > 1 || abs(f.width - base.width) > 1
                    state = "search \(f) \(moved ? "SHIFTED" : "ok")"
                } else { state = "search missing" }
                log("g\(index) (\(sx),\(sy))->(\(ex),\(ey)) long=\(long): \(state)")
                if state.contains("SHIFTED") {
                    let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = "shifted-\(index)"; a.lifetime = .keepAlways; add(a)
                    log("TREE g\(index): \(app.debugDescription)")
                }
            }
        }
    }
}
