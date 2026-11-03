import GlassUI
import SwiftUI

/// The screens the screenshot harness can show, selected with `-screenshot <rawValue>`.
/// To add a screen, add a case here and a test in `UITests/ScreenshotTests.swift` (see AGENTS.md).
enum ScreenshotScreen: String, CaseIterable {
    /// The placeholder root view.
    case root

    #if DEBUG
        /// GlassUI's gallery, every section (debug builds only).
        case gallery
        /// One section of GlassUI's gallery each, so a screenshot shows the whole section.
        case galleryColors = "gallery-colors"
        case galleryModes = "gallery-modes"
        case galleryTypography = "gallery-typography"
        case galleryLayout = "gallery-layout"
    #endif

    @MainActor @ViewBuilder
    var view: some View {
        switch self {
        case .root: RootView()
        #if DEBUG
            case .gallery: GlassUIGallery()
            case .galleryColors: GlassUIGallery(sections: [.colors])
            case .galleryModes: GlassUIGallery(sections: [.modes])
            case .galleryTypography: GlassUIGallery(sections: [.typography])
            case .galleryLayout: GlassUIGallery(sections: [.layout])
        #endif
        }
    }

    /// The accessibility identifier the harness puts on the screen, which the UI test waits for before capturing.
    var accessibilityIdentifier: String {
        "screenshot.\(rawValue)"
    }
}
