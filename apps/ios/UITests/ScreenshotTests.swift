import XCTest

/// Captures each harness screen as named PNG attachments, which `scripts/ci/ios.sh` exports to `build/screenshots/`.
/// Add one test per screen that calls `capture(_:fixtures:)` with the screen's `-screenshot` name (see AGENTS.md).
@MainActor
final class ScreenshotTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    // The map home (S2): the home sheet at each detent, and the banner outside New York.

    func testHomePeek() {
        capture("home-peek", fixtures: "nyc-evening", settledWhen: "map.settled")
    }

    func testHomeHalf() {
        capture("home-half", fixtures: "nyc-evening", settledWhen: "home.search")
    }

    func testHomeFull() {
        capture("home-full", fixtures: "nyc-evening", settledWhen: "home.search")
    }

    func testHomeOutsideNYC() {
        capture("home-outside-nyc", fixtures: "nyc-evening", settledWhen: "map.settled")
    }

    // Place search (S3) in the home sheet, in each state, and a picked place's pin and card.

    func testSearchEmpty() {
        capture("search-empty", fixtures: "nyc-evening", settledWhen: "search.hint")
    }

    func testSearchTyping() {
        capture("search-typing", fixtures: "slow-network", settledWhen: "search.loading")
    }

    func testSearchResults() {
        capture("search-results", fixtures: "nyc-evening", settledWhen: "search.results")
    }

    func testSearchNoResults() {
        capture("search-no-results", fixtures: "nyc-evening", settledWhen: "search.no-results")
    }

    func testSearchError() {
        capture("search-error", fixtures: "offline", settledWhen: "search.error")
    }

    func testSearchNoKey() {
        capture("search-no-key", fixtures: "no-key", settledWhen: "search.unavailable")
    }

    func testSearchPlace() {
        capture("search-place", fixtures: "nyc-evening", settledWhen: "map.settled")
    }

    // Journey options (J1) from Union Square to Grand Central Terminal: the list at each detent, a selected route on
    // the map, the arrive-by picker, and each state.

    func testJourneysPeek() {
        capture("journeys-peek", fixtures: "nyc-evening", settledWhen: "map.settled")
    }

    func testJourneysHalf() {
        capture("journeys-half", fixtures: "nyc-evening", settledWhen: "journeys.list")
    }

    func testJourneysFull() {
        capture("journeys-full", fixtures: "nyc-evening", settledWhen: "journeys.list")
    }

    func testJourneysRoute() {
        capture("journeys-route", fixtures: "nyc-evening", settledWhen: "map.settled")
    }

    func testJourneysArriveBy() {
        capture("journeys-arrive-by", fixtures: "nyc-evening", settledWhen: "journeys.time-picker")
    }

    func testJourneysLoading() {
        capture("journeys-loading", fixtures: "slow-network", settledWhen: "journeys.loading")
    }

    func testJourneysNoResults() {
        capture("journeys-no-results", fixtures: "no-journeys", settledWhen: "journeys.no-results")
    }

    func testJourneysOutsideNYC() {
        capture("journeys-outside-nyc", fixtures: "nyc-evening", settledWhen: "journeys.outside-area")
    }

    func testJourneysLocationOff() {
        capture("journeys-location-off", fixtures: "nyc-evening", settledWhen: "journeys.location-off")
    }

    func testJourneysError() {
        capture("journeys-error", fixtures: "offline", settledWhen: "journeys.error")
    }

    func testJourneysStale() {
        capture("journeys-stale", fixtures: "stale-data", settledWhen: "journeys.may-not-be-real-time")
    }

    // The About sheet (S1), over the home sheet.

    func testAbout() {
        capture("about", fixtures: "nyc-evening", settledWhen: "about.sheet")
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

    func testGalleryLines() {
        capture("gallery-lines", fixtures: "nyc-evening")
    }

    func testGalleryJourneys() {
        capture("gallery-journeys", fixtures: "nyc-evening")
    }

    func testGalleryDepartures() {
        capture("gallery-departures", fixtures: "nyc-evening")
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
    /// `<screen>-<fixtures>-<variant>` (such as `go-nyc-evening-dark`).
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
