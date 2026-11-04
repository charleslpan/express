import SwiftUI

/// The Saved tab: a placeholder until the Saved places task fills it with home, work, and saved places and lines.
struct SavedView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.savedPath) {
            ContentUnavailableView(
                "No Saved Places",
                systemImage: "bookmark",
                description: Text("Save home, work, and the places you go often to plan trips there in one tap.")
            )
            .navigationTitle("Saved")
        }
    }
}

#Preview {
    SavedView()
        .environment(AppRouter(selectedTab: .saved))
}
