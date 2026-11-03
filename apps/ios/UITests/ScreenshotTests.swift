import XCTest

/// Captures each harness screen as named PNG attachments, which `scripts/ci/ios.sh` exports to `build/screenshots/`.
/// Add one test per screen that calls `capture(_:fixtures:)` with the screen's `-screenshot` name (see AGENTS.md).
@MainActor
final class ScreenshotTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testRoot() {
        capture("root", fixtures: "nyc-evening")
    }

    // MARK: - Harness

    /// The appearance and text size combinations every screen is captured in.
    private enum Variant: String, CaseIterable {
        case light
        case dark
        case largestText = "light-ax5"

        var arguments: [String] {
            switch self {
            case .light: ["-appearance", "light"]
            case .dark: ["-appearance", "dark"]
            case .largestText:
                [
                    "-appearance", "light",
                    "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
                ]
            }
        }
    }

    /// Launches the app on `screen` with `fixtures` in every variant and attaches a screenshot of each, named
    /// `<screen>-<fixtures>-<variant>` (such as `root-nyc-evening-dark`).
    private func capture(_ screen: String, fixtures: String) {
        for variant in Variant.allCases {
            let app = XCUIApplication()
            app.launchArguments = ["-screenshot", screen, "-fixtures", fixtures] + variant.arguments
            app.launch()
            let ready = app.descendants(matching: .any)["screenshot.\(screen)"]
            XCTAssertTrue(ready.waitForExistence(timeout: 15), "\(screen) never appeared")

            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "\(screen)-\(fixtures)-\(variant.rawValue)"
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
    }
}
