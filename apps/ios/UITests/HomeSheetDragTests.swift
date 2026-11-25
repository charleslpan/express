import XCTest

/// The home sheet scrolls up and down only: a sideways drag along it must not move its content or push any of it off
/// the screen, at the default text size and at the largest accessibility size.
@MainActor
final class HomeSheetDragTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testHomeHalfDoesNotDragSideways() {
        assertNoSidewaysDrag("home-half")
    }

    func testHomeFullDoesNotDragSideways() {
        assertNoSidewaysDrag("home-full")
    }

    /// Drags right and left along the sheet at a few heights, each drag starting and ending in the sheet's side margins
    /// so a button under the finger can't take it as a tap, and holding at the end so a bounce would show. After each,
    /// the search field and what's under it must sit where they did and inside the screen.
    private func assertNoSidewaysDrag(_ screen: String) {
        let variants: [(name: String, arguments: [String])] = [
            ("default", []),
            ("ax5", ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]),
        ]
        for variant in variants {
            let app = XCUIApplication()
            app.launchArguments = ["-screenshot", screen, "-fixtures", "nyc-evening", "-appearance", "light"]
                + variant.arguments
            app.launch()
            XCTAssertTrue(app.descendants(matching: .any)["screenshot.\(screen)"].waitForExistence(timeout: 15))
            let search = app.descendants(matching: .any)["home.search"]
            XCTAssertTrue(search.waitForExistence(timeout: 20), "\(screen) \(variant.name): no search field")
            let window = app.windows.firstMatch
            let before = search.frame
            let watched = ["home.search", "alerts.chip", "home.places"].map { app.descendants(matching: .any)[$0] }

            for y in [0.55, 0.7, 0.85] {
                let left = window.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: y))
                let right = window.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: y))
                for (direction, from, to) in [("right", left, right), ("left", right, left)] {
                    from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.5)
                    let context = "\(screen) \(variant.name), dragged \(direction) at \(y)"
                    XCTAssertEqual(search.frame.minX, before.minX, accuracy: 1, "\(context): content moved")
                    for element in watched where element.exists {
                        XCTAssertGreaterThanOrEqual(element.frame.minX, 0, "\(context): \(element) starts off screen")
                        XCTAssertLessThanOrEqual(
                            element.frame.maxX, window.frame.width + 0.5, "\(context): \(element) runs off screen"
                        )
                    }
                }
            }
            app.terminate()
        }
    }
}
