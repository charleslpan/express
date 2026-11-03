import Foundation
import SwiftUI

/// What the process was launched with. Normally empty; the screenshot harness (`UITests/`) launches the app with
/// `-screenshot <screen> -fixtures <set> [-appearance light|dark]` to show one screen, on fixture data, in a fixed
/// appearance. Text size comes from the system's own `-UIPreferredContentSizeCategoryName` argument.
struct LaunchConfiguration: Equatable {
    /// The screen to show instead of the app's root, from `-screenshot <name>`.
    var screen: ScreenshotScreen?
    /// The fixture set to back the data clients with, from `-fixtures <name>`.
    var fixtures: FixtureSet?
    /// The appearance to force, from `-appearance light|dark`; nil follows the system.
    var colorScheme: ColorScheme?

    /// Whether this launch is the screenshot harness's, which turns off animations so captures are deterministic.
    var isScreenshot: Bool {
        screen != nil
    }

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        let values = Self.values(in: arguments)
        screen = values["screenshot"].flatMap(ScreenshotScreen.init(rawValue:))
        fixtures = values["fixtures"].flatMap(FixtureSet.init(rawValue:))
        colorScheme = switch values["appearance"] {
        case "light"?: .light
        case "dark"?: .dark
        default: nil
        }
    }

    /// `-key value` pairs, the shape Xcode and XCUIApplication pass launch arguments in.
    private static func values(in arguments: [String]) -> [String: String] {
        var values: [String: String] = [:]
        for (key, value) in zip(arguments, arguments.dropFirst()) where key.hasPrefix("-") && !value.hasPrefix("-") {
            values[String(key.dropFirst())] = value
        }
        return values
    }
}
