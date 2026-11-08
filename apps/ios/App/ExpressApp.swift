import SwiftUI
import TransitKit
import UIKit

@main
struct ExpressApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let launch = LaunchConfiguration()
    @State private var environment: AppEnvironment
    @State private var router: AppRouter
    @State private var location: LocationService
    @State private var places: PlaceStore
    /// The app's one ``TransitClient``: on the fixture set's recorded data for the screenshot harness, else live.
    private let transitClient: TransitClient
    private let placeSearchService: (any PlaceSearchService)?

    init() {
        let environment = AppEnvironment(fixtures: launch.fixtures)
        _environment = State(initialValue: environment)
        transitClient = launch.fixtures?.transitClient ?? TransitClient(baseURL: ExpressApp.transitServer.baseURL)
        let screen = launch.screen
        let router = AppRouter(homeDetent: screen?.homeDetent ?? .peek, sheet: screen?.sheet)
        screen?.prepare(router)
        _router = State(initialValue: router)
        // The screenshot harness never asks for the location; it fixes the permission each screen shows.
        let location = screen
            .map { LocationService(fixed: $0.locationAuthorization, location: $0.location) } ?? LocationService()
        _location = State(initialValue: location)
        GoogleMapsServices.configure()
        let placeSearchService = PlaceSearchServices.make(fixtures: launch.fixtures)
        self.placeSearchService = placeSearchService
        // Recents and saved places, on disk; launches on fixtures (the screenshot harness) keep theirs in memory, on
        // the fixtures' clock, so they never touch the real store.
        let lookup = PlaceLookupServices.make(fixtures: launch.fixtures, search: placeSearchService)
        let places = launch.fixtures == nil && !launch.isScreenshot
            ? PlaceStore.persistent(lookup: lookup)
            : PlaceStore.inMemory(lookup: lookup, now: { environment.now })
        screen?.prepare(places)
        _places = State(initialValue: places)
        if launch.isScreenshot {
            UIView.setAnimationsEnabled(false)
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let screen = launch.screen {
                    screen.view
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier(screen.accessibilityIdentifier)
                } else {
                    RootView()
                }
            }
            .environment(environment)
            .environment(router)
            .environment(location)
            .environment(places)
            .environment(\.transitClient, transitClient)
            .environment(\.placeSearchService, placeSearchService)
            .environment(\.placeSearchSeed, launch.screen?.searchQuery)
            .environment(\.journeyOptionsSeed, launch.screen?.journeyOptionsSeed)
            .preferredColorScheme(launch.colorScheme)
        }
        .onChange(of: scenePhase) { _, phase in
            // One cheap request as the app comes to the foreground, so the first search lands on a warm server.
            // Never on a timer, and never for the screenshot harness, which stays off the network.
            guard phase == .active, !launch.isScreenshot else { return }
            Task { await transitClient.warmUp() }
        }
    }

    /// The MOTIS server the app talks to: Express's own, or in debug builds Transitous when launched with
    /// `-TransitServer transitous` (Edit Scheme → Run → Arguments).
    static var transitServer: TransitServer {
        #if DEBUG
            if let name = UserDefaults.standard.string(forKey: "TransitServer"),
               let server = TransitServer(rawValue: name)
            {
                return server
            }
        #endif
        return .express
    }
}

extension EnvironmentValues {
    /// The app's one ``TransitClient``, pointed at ``ExpressApp/transitServer``.
    @Entry var transitClient = TransitClient()
}
