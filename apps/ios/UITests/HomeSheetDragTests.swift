import XCTest

/// The home sheet scrolls up and down only: a sideways drag on it must not move its content, at the default text size
/// and at the largest accessibility size, with each state of Nearby that can be wider than the screen.
@MainActor
final class HomeSheetDragTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testHomeHalf() {
        assertNoSidewaysDrag("home-half", settledWhen: "home.search")
    }

    func testHomeFull() {
        assertNoSidewaysDrag("home-full", settledWhen: "home.search")
    }

    func testNearbyOutsideNYC() {
        assertNoSidewaysDrag("nearby-outside-nyc", settledWhen: "nearby.outside-nyc")
    }

    func testNearbyFull() {
        assertNoSidewaysDrag("nearby-full", settledWhen: "nearby.loaded")
    }

    private func assertNoSidewaysDrag(_ screen: String, settledWhen settled: String) {
        let variants: [(name: String, arguments: [String])] = [
            ("light", ["-appearance", "light"]),
            ("light-ax5", ["-appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]),
        ]
        for variant in variants {
            let app = XCUIApplication()
            app.launchArguments = ["-screenshot", screen, "-fixtures", "nyc-evening"] + variant.arguments
            app.launch()
            XCTAssertTrue(app.descendants(matching: .any)["screenshot.\(screen)"].waitForExistence(timeout: 15))
            _ = app.descendants(matching: .any)[settled].waitForExistence(timeout: 30)
            let search = app.descendants(matching: .any)["home.search"]
            XCTAssertTrue(search.waitForExistence(timeout: 10))
            let window = app.windows.firstMatch
            let before = search.frame
            attach(app, "\(screen)-\(variant.name)-0-before")

            // Drag right and left along the sheet, each drag starting and ending in the 16 pt margins so a button
            // under the finger can't take it as a tap, holding at the end so a bounce would show.
            let identifiers = ["home.search", "alerts.chip", "home.places", settled]
            for y in [0.55, 0.7, 0.85] {
                let left = window.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: y))
                let right = window.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: y))
                for (name, from, to) in [("right", left, right), ("left", right, left)] {
                    from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.5)
                    attach(app, "\(screen)-\(variant.name)-\(name)-\(y)")
                    XCTAssertEqual(search.frame.minX, before.minX, accuracy: 1, "\(screen) \(variant.name): dragged \(name) at \(y)")
                    for identifier in identifiers {
                        let element = app.descendants(matching: .any)[identifier]
                        guard element.exists else { continue }
                        XCTAssertGreaterThanOrEqual(element.frame.minX, 0, "\(identifier) starts off screen")
                        XCTAssertLessThanOrEqual(element.frame.maxX, window.frame.width + 0.5, "\(identifier) runs off screen")
                    }
                }
            }
            app.terminate()
        }
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
