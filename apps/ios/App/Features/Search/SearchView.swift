import SwiftUI

/// The search tab: a placeholder until place search (S3) fills it with suggestions and results.
struct SearchView: View {
    @Environment(AppRouter.self) private var router
    @State private var query = ""

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.searchPath) {
            ContentUnavailableView(
                "Where To?",
                systemImage: "magnifyingglass",
                description: Text("Search for a place, an address, or a station to plan a trip there.")
            )
            .navigationTitle("Search")
        }
        .searchable(text: $query, prompt: "Places, addresses, stations")
    }
}

#Preview {
    SearchView()
        .environment(AppRouter(selectedTab: .search))
}
