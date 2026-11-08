import Observation
import SwiftUI
import TransitKit

/// How far the home sheet is pulled up over the map.
enum HomeSheetDetent: String, CaseIterable, Hashable {
    /// Just the search field, with the map filling the screen.
    case peek
    /// About half the screen: search, Home and Work, and the start of Nearby, with the map still usable above.
    case half
    /// Nearly the whole screen: every section, scrolling.
    case full
}

/// A sheet the shell presents over the home sheet.
enum AppSheet: String, Identifiable {
    case about

    var id: String {
        rawValue
    }
}

/// Where the app is: how far the home sheet is pulled up, the navigation stack inside it, and the sheet on top.
///
/// The app is one screen, Apple Maps style: the map, with the home sheet over it that never goes away. Views never
/// wire navigation themselves: they read the router from the environment (`@Environment(AppRouter.self)`) and call a
/// method that says where to go. Features add their own methods in an extension in their folder, such as
/// `showDepartures(from:)` pushing a value onto ``homePath`` and raising the sheet, and register a
/// `navigationDestination(for:)` for that value in the sheet's stack.
@MainActor
@Observable
final class AppRouter {
    /// How far the home sheet is pulled up.
    var homeDetent: HomeSheetDetent
    /// The navigation stack inside the home sheet.
    var homePath = NavigationPath()
    /// Whether the home sheet is showing place search in place of its sections (``showPlaceSearch()``).
    var isSearchingPlaces = false
    /// The place picked from search, pinned on the map with its card in the home sheet (``showPlace(_:)``). Journeys
    /// and saved places start from it. Held in memory only: Express persists nothing of a place but its ID.
    var selectedPlace: PlaceDetails?
    /// The sheet shown over the home sheet, if any.
    var sheet: AppSheet?

    init(homeDetent: HomeSheetDetent = .peek, sheet: AppSheet? = nil) {
        self.homeDetent = homeDetent
        self.sheet = sheet
    }

    /// Empties the home sheet's navigation stack.
    func popToRoot() {
        homePath = NavigationPath()
    }

    func showAbout() {
        sheet = .about
    }

    func dismissSheet() {
        sheet = nil
    }
}
