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

    func testMapGlass() {
        capture("map-glass", fixtures: "nyc-evening", settledWhen: "map.settled")
    }

    // GlassUI's gallery, one section per screen. The gallery shows no transit data; the fixtures only fix the clock.

    func testGalleryColors() {
        capture("gallery-colors", fixtures: "nyc-evening")
    }

    func testGalleryModes() {
        capture("gallery-modes", fixtures: "nyc-evening")
    }

    func testGalleryTypography() {
        capture("gallery-typography", fixtures: "nyc-evening")
    }

    func testGalleryLayout() {
        capture("gallery-layout", fixtures: "nyc-evening")
    }

    func testGalleryControls() {
        capture("gallery-controls", fixtures: "nyc-evening")
    }

    func testGalleryControlStates() {
        capture("gallery-control-states", fixtures: "nyc-evening")
    }

    func testGalleryControlFallbacks() {
        capture("gallery-control-fallbacks", fixtures: "nyc-evening")
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
    ///
    /// `settledWhen` names an element the screen shows once it has finished loading what the network serves it,
    /// such as map tiles; the capture waits for it a while, then goes ahead without it rather than fail.
    private func capture(_ screen: String, fixtures: String, settledWhen settled: String? = nil) {
        for variant in Variant.allCases {
            let app = XCUIApplication()
            app.launchArguments = ["-screenshot", screen, "-fixtures", fixtures] + variant.arguments
            app.launch()
            let ready = app.descendants(matching: .any)["screenshot.\(screen)"]
            XCTAssertTrue(ready.waitForExistence(timeout: 15), "\(screen) never appeared")
            if let settled, !app.descendants(matching: .any)[settled].waitForExistence(timeout: 30) {
                XCTContext.runActivity(named: "\(screen) never showed \(settled); capturing anyway") { _ in }
            }

            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "\(screen)-\(fixtures)-\(variant.rawValue)"
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
    }
}
