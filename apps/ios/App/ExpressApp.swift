import SwiftUI
import TransitKit

@main
struct ExpressApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let transitClient = TransitClient(baseURL: ExpressApp.transitServer.baseURL)

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.transitClient, transitClient)
        }
        .onChange(of: scenePhase) { _, phase in
            // One cheap request as the app comes to the foreground, so the first search lands on a warm server.
            // Never on a timer.
            guard phase == .active else { return }
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
