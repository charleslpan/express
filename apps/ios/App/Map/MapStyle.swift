import Foundation
import GoogleMaps
import SwiftUI

/// Express's map styling: muted JSON styles for light and dark, swapped with the color scheme.
///
/// Styles are JSON (`Styles/map-style-*.json`), never a cloud map ID: map loads without a map ID are free and
/// unlimited, while a map ID (cloud styling, advanced markers) makes them billed. They mute the base map, turn
/// business POIs off, and tone Google's transit layer down so Express's own lines read on top.
enum MapStyle {
    /// The style for `colorScheme`, or nil (Google's default) where its file is missing or invalid.
    @MainActor
    static func style(for colorScheme: ColorScheme) -> GMSMapStyle? {
        let name = colorScheme == .dark ? "map-style-dark" : "map-style-light"
        if let cached = cache[name] {
            return cached
        }
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let style = try? GMSMapStyle(contentsOfFileURL: url)
        else {
            assertionFailure("Missing or invalid map style \(name).json")
            return nil
        }
        cache[name] = style
        return style
    }

    @MainActor private static var cache: [String: GMSMapStyle] = [:]
}
