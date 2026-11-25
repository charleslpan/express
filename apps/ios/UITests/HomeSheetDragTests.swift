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

    /// The Saved section's rows swipe to unsave under the finger, but a sideways drag on the heading above them must
    /// move nothing on the sheet.
    func testSavedSectionStaysPutOutsideItsRows() {
        for ax5 in [false, true] {
            let app = XCUIApplication()
            app.launchArguments = ["-screenshot", "home-saved", "-fixtures", "nyc-evening", "-appearance", "light"]
                + (ax5 ? ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] : [])
            app.launch()
            XCTAssertTrue(app.descendants(matching: .any)["home.saved"].waitForExistence(timeout: 30))
            let heading = app.descendants(matching: .any)["home.saved.heading"]
            let window = app.windows.firstMatch
            for _ in 0 ..< 10 {
                guard heading.exists, !(heading.isHittable && heading.frame.minY < window.frame.midY) else { break }
                let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
                let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
                start.press(forDuration: 0.05, thenDragTo: end)
            }
            let tag = ax5 ? "ax5" : "default"
            func frames() -> [String: CGRect] {
                var result: [String: CGRect] = [:]
                for (index, element) in app.buttons.allElementsBoundByIndex.enumerated() where element.exists {
                    result["button \(index) \(element.label)"] = element.frame
                }
                result["heading"] = heading.frame
                return result
            }
            let before = frames()
            attach(app, "saved-\(tag)-before")
            let y = heading.frame.midY / window.frame.height
            let left = window.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: y))
            let right = window.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: y))
            let middle = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: y))
            for (name, from, to) in [("right", left, right), ("left", right, left), ("mid-left", middle, left), ("mid-right", middle, right)] {
                from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.5)
                attach(app, "saved-\(tag)-\(name)")
                let after = frames()
                for (key, frame) in before {
                    guard let moved = after[key] else { continue }
                    XCTAssertEqual(moved.minX, frame.minX, accuracy: 1, "\(tag): \(key) moved sideways after dragging \(name) on the heading")
                }
            }
            app.terminate()
        }
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
