import GlassUI
import SwiftUI
import TransitKit

/// The screens the screenshot harness can show, selected with `-screenshot <rawValue>`.
/// To add a screen, add a case here and a test in `UITests/ScreenshotTests.swift` (see AGENTS.md).
enum ScreenshotScreen: String, CaseIterable {
    /// The app shell on each tab, and with the About sheet up (S1).
    case go
    case nearby
    /// Nearby when Express may not use the location: the friendly denied state.
    case nearbyLocationOff = "nearby-location-off"
    case saved
    case search
    case about
    /// The map home while the user is outside New York, with the banner saying Express covers the city (S2).
    case homeOutsideNYC = "home-outside-nyc"
    /// Liquid Glass controls and a glass sheet over the Google map, for judging the look (F5).
    case mapGlass = "map-glass"

    #if DEBUG
        /// GlassUI's gallery, every section (debug builds only).
        case gallery
        /// One section of GlassUI's gallery each, so a screenshot shows the whole section.
        case galleryColors = "gallery-colors"
        case galleryModes = "gallery-modes"
        case galleryTypography = "gallery-typography"
        case galleryLayout = "gallery-layout"
        case galleryLines = "gallery-lines"
        case galleryJourneys = "gallery-journeys"
        case galleryDepartures = "gallery-departures"
        case galleryControls = "gallery-controls"
        case galleryControlStates = "gallery-control-states"
        case galleryControlFallbacks = "gallery-control-fallbacks"
    #endif

    @MainActor @ViewBuilder
    var view: some View {
        switch self {
        case .go, .nearby, .nearbyLocationOff, .saved, .search, .about, .homeOutsideNYC: RootView()
        case .mapGlass: MapGlassScreen()
        #if DEBUG
            case .gallery: GlassUIGallery()
            case .galleryColors: GlassUIGallery(sections: [.colors])
            case .galleryModes: GlassUIGallery(sections: [.modes])
            case .galleryTypography: GlassUIGallery(sections: [.typography])
            case .galleryLayout: GlassUIGallery(sections: [.layout])
            case .galleryLines: GlassUIGallery(sections: [.lines])
            case .galleryJourneys: GlassUIGallery(sections: [.journeys])
            case .galleryDepartures: GlassUIGallery(sections: [.departures])
            case .galleryControls: GlassUIGallery(sections: [.controls])
            case .galleryControlStates: GlassUIGallery(sections: [.controlStates])
            case .galleryControlFallbacks: GlassUIGallery(sections: [.controlFallbacks])
        #endif
        }
    }

    /// The tab the shell opens on for this screen.
    var tab: AppTab {
        switch self {
        case .nearby, .nearbyLocationOff: .nearby
        case .saved: .saved
        case .search: .search
        default: .go
        }
    }

    /// The sheet the shell opens with for this screen.
    var sheet: AppSheet? {
        self == .about ? .about : nil
    }

    /// The location permission the screen shows; the harness never asks for it.
    var locationAuthorization: LocationService.Authorization {
        switch self {
        case .nearbyLocationOff: .denied
        case .homeOutsideNYC: .authorized
        default: .notDetermined
        }
    }

    /// The location the screen shows the user at, if any: Philadelphia's City Hall for the outside-NYC banner.
    var location: Coordinate? {
        self == .homeOutsideNYC ? Coordinate(latitude: 39.9526, longitude: -75.1652) : nil
    }

    /// The accessibility identifier the harness puts on the screen, which the UI test waits for before capturing.
    var accessibilityIdentifier: String {
        "screenshot.\(rawValue)"
    }
}
