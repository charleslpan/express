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
    /// The server's client, or one answering from the launch's fixtures (``FixtureSet/transitClient``).
    private let transitClient: TransitClient
    private let placeSearchService: (any PlaceSearchService)?

    init() {
        _environment = State(initialValue: AppEnvironment(fixtures: launch.fixtures))
        transitClient = launch.fixtures?.transitClient ?? TransitClient(baseURL: Self.transitServer.baseURL)
        let screen = launch.screen
        let router = AppRouter(homeDetent: screen?.homeDetent ?? .peek, sheet: screen?.sheet)
        screen?.prepare(router)
        _router = State(initialValue: router)
        // The screenshot harness never asks for the location; it fixes the permission each screen shows.
        let location = screen
            .map { LocationService(fixed: $0.locationAuthorization, location: $0.location) } ?? LocationService()
        _location = State(initialValue: location)
        GoogleMapsServices.configure()
        placeSearchService = PlaceSearchServices.make(fixtures: launch.fixtures)
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
            .environment(\.transitClient, transitClient)
            .environment(\.placeSearchService, placeSearchService)
            .environment(\.placeSearchSeed, launch.screen?.searchQuery)
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
