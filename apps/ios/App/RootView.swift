import SwiftUI

/// The app shell: the Liquid Glass tab bar over Go (the map home), Nearby, Saved, and search, and the sheets the
/// ``AppRouter`` presents over them. It reads the router and the location service from the environment, which
/// `ExpressApp` (or the screenshot harness) injects.
struct RootView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: tabSelection) {
            Tab("Go", systemImage: "map", value: AppTab.go) {
                GoView()
            }
            Tab("Nearby", systemImage: "location.circle", value: AppTab.nearby) {
                NearbyView()
            }
            Tab("Saved", systemImage: "bookmark", value: AppTab.saved) {
                SavedView()
            }
            Tab(value: AppTab.search, role: .search) {
                SearchView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .sheet(item: $router.sheet) { sheet in
            switch sheet {
            case .about: AboutView()
            }
        }
    }

    /// The tab bar's selection, through ``AppRouter/select(_:)`` so tapping the current tab pops it to its root.
    private var tabSelection: Binding<AppTab> {
        Binding {
            router.selectedTab
        } set: { tab in
            router.select(tab)
        }
    }
}

#Preview("Go") {
    RootView()
        .environment(AppRouter())
        .environment(LocationService(fixed: .notDetermined))
}

#Preview("About") {
    RootView()
        .environment(AppRouter(sheet: .about))
        .environment(LocationService(fixed: .authorized))
}
