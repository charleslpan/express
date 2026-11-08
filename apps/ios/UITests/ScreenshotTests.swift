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

    // Nearby (N1) in the home sheet at Union Square: the peek's next trains, then more stops at half and full height.

    func testNearbyPeek() {
        capture("nearby-peek", fixtures: "nyc-evening", settledWhen: "nearby.loaded", "map.settled")
    }

    func testNearbyHalf() {
        capture("nearby-half", fixtures: "nyc-evening", settledWhen: "nearby.loaded")
    }

    func testNearbyFull() {
        capture("nearby-full", fixtures: "nyc-evening", settledWhen: "nearby.loaded")
    }

    // Nearby's other states: times that may not be real time, location off, outside New York, loading, offline, and
    // nothing due. (Before the location is allowed, the home screens above show Nearby asking for it.)

    func testNearbyStale() {
        capture("nearby-stale", fixtures: "nyc-evening-stale", settledWhen: "nearby.not-real-time")
    }

    func testNearbyDenied() {
        capture("nearby-denied", fixtures: "nyc-evening", settledWhen: "nearby.location-off")
    }

    func testNearbyOutsideNYC() {
        capture("nearby-outside-nyc", fixtures: "nyc-evening", settledWhen: "nearby.outside-nyc")
    }

    func testNearbyLoading() {
        capture("nearby-loading", fixtures: "slow-network", settledWhen: "nearby.loading")
    }

    func testNearbyError() {
        capture("nearby-error", fixtures: "offline", settledWhen: "nearby.failed")
    }

    func testNearbyEmpty() {
        capture("nearby-empty", fixtures: "nyc-no-service", settledWhen: "nearby.empty")
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

    // Recents and saved places (P1): recents in search before you type, and the place card's Save and Home or Work.

    func testSearchRecents() {
        capture("search-recents", fixtures: "nyc-evening", settledWhen: "search.recents")
    }

    func testPlaceSaved() {
        capture("place-saved", fixtures: "nyc-evening", settledWhen: "map.settled")
    }

    func testPlaceHomeWork() {
        capture("place-home-work", fixtures: "nyc-evening", settledWhen: "map.settled") { app in
            app.buttons["place.slots"].tap()
            let menuOpened = app.buttons["Set as Home"].waitForExistence(timeout: 10)
            XCTAssertTrue(menuOpened, "The Home or Work menu never opened")
        }
    }

    // The About sheet (S1), over the home sheet.

    func testAbout() {
        capture("about", fixtures: "nyc-evening", settledWhen: "about.sheet")
    }

    func testMapGlass() {
        capture("map-glass", fixtures: "nyc-evening", settledWhen: "map.settled")
    }

    // Live subway trains (V1): over Midtown, hidden when zoomed out, and with the notice when live data is stale.

    func testTrains() {
        capture("trains", fixtures: "nyc-evening", settledWhen: "map.settled")
    }

    func testTrainsZoomedOut() {
        capture("trains-zoomed-out", fixtures: "nyc-evening", settledWhen: "map.settled")
    }

    func testTrainsStale() {
        capture("trains", fixtures: "nyc-evening-stale", settledWhen: "trains.notice")
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
    /// `settledWhen` names elements the screen shows once it has finished loading what it shows, such as map tiles
    /// or departures; the capture waits for each a while, then goes ahead without it rather than fail. `then` runs
    /// before each capture, to put the screen in a state only a tap reaches, such as an open menu.
    private func capture(
        _ screen: String,
        fixtures: String,
        settledWhen settled: String...,
        then prepare: ((XCUIApplication) -> Void)? = nil
    ) {
        for variant in Variant.allCases {
            let app = XCUIApplication()
            app.launchArguments = ["-screenshot", screen, "-fixtures", fixtures] + variant.arguments
            app.launch()
            let ready = app.descendants(matching: .any)["screenshot.\(screen)"]
            XCTAssertTrue(ready.waitForExistence(timeout: 15), "\(screen) never appeared")
            for settled in settled where !app.descendants(matching: .any)[settled].waitForExistence(timeout: 30) {
                XCTContext.runActivity(named: "\(screen) never showed \(settled); capturing anyway") { _ in }
            }
            prepare?(app)

            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "\(screen)-\(fixtures)-\(variant.rawValue)"
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
    }
}
