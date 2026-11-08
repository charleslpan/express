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
    /// Place search in the home sheet (S3): the hint for an empty query, a query typed while suggestions load, the
    /// suggestions, none found, a failure with Try Again, and "Search Unavailable" without a key. Which of the last
    /// states shows depends on the fixtures each test launches with.
    case searchEmpty = "search-empty"
    case searchTyping = "search-typing"
    case searchResults = "search-results"
    case searchNoResults = "search-no-results"
    case searchError = "search-error"
    case searchNoKey = "search-no-key"
    /// A place picked from search: its pin on the map and its card in the home sheet (S3), not saved (P1).
    case searchPlace = "search-place"
    /// Place search before you type, listing your recents with Clear (P1).
    case searchRecents = "search-recents"
    /// The place card for a saved place (P1).
    case placeSaved = "place-saved"
    /// The place card's Home or Work menu, open, for the place that's Work (P1); the UI test opens it.
    case placeHomeWork = "place-home-work"
    /// The About sheet over the home sheet (S1).
    case about
    /// Liquid Glass controls and a glass sheet over the Google map, for judging the look (F5).
    case mapGlass = "map-glass"
    /// Live subway trains over Midtown and Union Square, and the same map zoomed out, where they hide (V1).
    case trains
    case trainsZoomedOut = "trains-zoomed-out"

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
        case .homePeek, .homeHalf, .homeFull, .homeOutsideNYC, .about, .searchEmpty, .searchTyping, .searchResults,
             .searchNoResults, .searchError, .searchNoKey, .searchPlace, .searchRecents, .placeSaved, .placeHomeWork:
            RootView()
        case .mapGlass: MapGlassScreen()
        case .trains: GoView(camera: MapCamera(center: Self.midtown, zoom: 14.5))
        case .trainsZoomedOut: GoView(camera: MapCamera(center: Self.midtown, zoom: 11.5))
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
        case .homeHalf: .half
        case .homeFull: .full
        default: .peek
        }
    }

    /// The sheet the shell opens with for this screen.
    var sheet: AppSheet? {
        self == .about ? .about : nil
    }

    /// The query a search screen opens with, as if typed; nil leaves the field empty.
    var searchQuery: String? {
        switch self {
        case .searchEmpty, .searchNoKey, .searchRecents: ""
        case .searchTyping: "Grand Cen"
        case .searchResults, .searchError: "Grand"
        case .searchNoResults: "Qwxyz"
        default: nil
        }
    }

    /// Puts the router where this screen starts: searching, or showing a picked place.
    @MainActor
    func prepare(_ router: AppRouter) {
        if searchQuery != nil {
            router.showPlaceSearch()
        } else if [.searchPlace, .placeSaved, .placeHomeWork].contains(self) {
            router.showPlace(FixturePlaceSearchService.places[0])
        }
    }

    /// Fills the in-memory place store with what this screen shows: recents picked over the past day, or the
    /// card's place saved, or Work with another place as Home.
    @MainActor
    func prepare(_ places: PlaceStore) {
        let fixtures = FixturePlaceSearchService.places
        switch self {
        case .searchRecents:
            let now = FixtureSet.nycEvening.referenceDate
            for (place, minutesAgo) in zip([fixtures[0], fixtures[1], fixtures[2], fixtures[4]], [5, 90, 1440, 4320]) {
                places.addRecent(place, pickedAt: now.addingTimeInterval(-Double(minutesAgo) * 60))
            }
        case .placeSaved:
            places.save(fixtures[0])
        case .placeHomeWork:
            places.set(.home, to: fixtures[2])
            places.set(.work, to: fixtures[0])
        default:
            break
        }
    }

    /// The location permission the screen shows; the harness never asks for it.
    var locationAuthorization: LocationService.Authorization {
        self == .homeOutsideNYC ? .authorized : .notDetermined
    }

    /// The location the screen shows the user at, if any: Philadelphia's City Hall for the outside-NYC banner.
    var location: Coordinate? {
        self == .homeOutsideNYC ? Coordinate(latitude: 39.9526, longitude: -75.1652) : nil
    }

    /// Where the trains screens look: between Union Square and Herald Square, where the `nyc-evening` trips run.
    private static let midtown = Coordinate(latitude: 40.7445, longitude: -73.9895)

    /// The accessibility identifier the harness puts on the screen, which the UI test waits for before capturing.
    var accessibilityIdentifier: String {
        "screenshot.\(rawValue)"
    }
}
