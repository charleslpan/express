import SwiftUI
import UIKit

@main
struct ExpressApp: App {
    private let launch = LaunchConfiguration()
    @State private var environment: AppEnvironment

    init() {
        _environment = State(initialValue: AppEnvironment(fixtures: launch.fixtures))
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
            .preferredColorScheme(launch.colorScheme)
        }
    }
}
