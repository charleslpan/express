import GlassUI
import SwiftUI
import TransitKit

/// The screens the screenshot harness can show, selected with `-screenshot <rawValue>`.
/// To add a screen, add a case here and a test in `UITests/ScreenshotTests.swift` (see AGENTS.md).
enum ScreenshotScreen: String, CaseIterable {
    /// The map home with its sheet at each detent (S2).
    case homePeek = "home-peek"
    case homeHalf = "home-half"
    case homeFull = "home-full"
    /// The map home while the user is outside New York, with the banner saying Express covers the city (S2).
    case homeOutsideNYC = "home-outside-nyc"
    /// The Nearby section in the home sheet at Union Square (N1): its peek (the nearest station's next trains), half,
    /// and full, with live and scheduled rows.
    case nearbyPeek = "nearby-peek"
    case nearbyHalf = "nearby-half"
    case nearbyFull = "nearby-full"
    /// Nearby's states other than departures (N1), each at half height: the "may not be real time" notice (with
    /// `-fixtures nyc-evening-stale`), the location turned off, outside New York, loading (`loading`), offline
    /// (`offline`), and nothing due (`nyc-no-service`).
    case nearbyStale = "nearby-stale"
    case nearbyDenied = "nearby-denied"
    case nearbyOutsideNYC = "nearby-outside-nyc"
    case nearbyLoading = "nearby-loading"
    case nearbyError = "nearby-error"
    case nearbyEmpty = "nearby-empty"
    /// The About sheet over the home sheet (S1).
    case about
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
        case .homePeek, .homeHalf, .homeFull, .homeOutsideNYC, .about, .nearbyPeek, .nearbyHalf, .nearbyFull,
             .nearbyStale, .nearbyDenied, .nearbyOutsideNYC, .nearbyLoading, .nearbyError, .nearbyEmpty: RootView()
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

    /// How far the home sheet is pulled up for this screen.
    var homeDetent: HomeSheetDetent {
        switch self {
        case .homeHalf, .nearbyHalf, .nearbyStale, .nearbyDenied, .nearbyOutsideNYC, .nearbyLoading, .nearbyError,
             .nearbyEmpty: .half
        case .homeFull, .nearbyFull: .full
        default: .peek
        }
    }

    /// The sheet the shell opens with for this screen.
    var sheet: AppSheet? {
        self == .about ? .about : nil
    }

    /// The location permission the screen shows; the harness never asks for it.
    var locationAuthorization: LocationService.Authorization {
        switch self {
        case .homeOutsideNYC, .nearbyPeek, .nearbyHalf, .nearbyFull, .nearbyStale, .nearbyOutsideNYC, .nearbyLoading,
             .nearbyError, .nearbyEmpty: .authorized
        case .nearbyDenied: .denied
        default: .notDetermined
        }
    }

    /// The location the screen shows the user at, if any: Philadelphia's City Hall outside New York, and Union Square
    /// (``FixtureSet/unionSquare``) for Nearby.
    var location: Coordinate? {
        switch self {
        case .homeOutsideNYC, .nearbyOutsideNYC: Coordinate(latitude: 39.9526, longitude: -75.1652)
        case .nearbyPeek, .nearbyHalf, .nearbyFull, .nearbyStale, .nearbyLoading, .nearbyError, .nearbyEmpty:
            FixtureSet.unionSquare
        default: nil
        }
    }

    /// The accessibility identifier the harness puts on the screen, which the UI test waits for before capturing.
    var accessibilityIdentifier: String {
        "screenshot.\(rawValue)"
    }
}
