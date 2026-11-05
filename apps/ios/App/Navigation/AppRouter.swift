import Observation
import SwiftUI

/// The app's tabs, in the order the tab bar shows them.
enum AppTab: String, CaseIterable, Hashable {
    /// The map home.
    case go
    case nearby
    case saved
    /// The search tab, which the tab bar draws apart from the others.
    case search
}

/// A sheet the shell presents over every tab.
enum AppSheet: String, Identifiable {
    case about

    var id: String {
        rawValue
    }
}

/// How far the Go tab's home sheet is pulled up over the map.
enum HomeSheetDetent: String, CaseIterable, Hashable {
    /// Just the search field, with the map filling the screen.
    case peek
    /// About half the screen: the search field, saved places, and the nearest departures.
    case half
    /// Nearly the whole screen, with the sheet's content scrolling.
    case full
}

/// Where the app is: the selected tab, each tab's navigation stack, and the sheet on top.
///
/// Views never wire navigation themselves: they read the router from the environment (`@Environment(AppRouter.self)`)
/// and call a method that says where to go. Features add their own methods in an extension in their folder, such as
/// `showJourneys(to:)` pushing a value onto ``goPath`` and selecting ``AppTab/go``, and register a
/// `navigationDestination(for:)` for that value in the tab's stack.
@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab
    /// The Go tab's stack, over the map home.
    var goPath = NavigationPath()
    var nearbyPath = NavigationPath()
    var savedPath = NavigationPath()
    var searchPath = NavigationPath()
    /// The sheet shown over the tabs, if any.
    var sheet: AppSheet?
    /// How far the Go tab's home sheet is pulled up.
    var homeDetent: HomeSheetDetent

    init(selectedTab: AppTab = .go, sheet: AppSheet? = nil, homeDetent: HomeSheetDetent = .peek) {
        self.selectedTab = selectedTab
        self.sheet = sheet
        self.homeDetent = homeDetent
    }

    /// Shows `tab`. Selecting the tab that is already showing pops it to its root, as the system's tab bars do.
    func select(_ tab: AppTab) {
        if tab == selectedTab {
            popToRoot(tab)
        }
        selectedTab = tab
    }

    /// Empties `tab`'s navigation stack.
    func popToRoot(_ tab: AppTab) {
        switch tab {
        case .go: goPath = NavigationPath()
        case .nearby: nearbyPath = NavigationPath()
        case .saved: savedPath = NavigationPath()
        case .search: searchPath = NavigationPath()
        }
    }

    /// Opens the search tab, for "where to?" from anywhere in the app.
    func showSearch() {
        selectedTab = .search
    }

    func showAbout() {
        sheet = .about
    }

    func dismissSheet() {
        sheet = nil
    }
}
