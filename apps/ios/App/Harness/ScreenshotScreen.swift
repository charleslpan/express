import SwiftUI

/// The screens the screenshot harness can show, selected with `-screenshot <rawValue>`.
/// To add a screen, add a case here and a test in `UITests/ScreenshotTests.swift` (see AGENTS.md).
enum ScreenshotScreen: String, CaseIterable {
    /// The placeholder root view.
    case root

    @MainActor @ViewBuilder
    var view: some View {
        switch self {
        case .root: RootView()
        }
    }

    /// The accessibility identifier the harness puts on the screen, which the UI test waits for before capturing.
    var accessibilityIdentifier: String {
        "screenshot.\(rawValue)"
    }
}
