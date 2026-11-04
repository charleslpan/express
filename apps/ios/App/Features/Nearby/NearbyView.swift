import GlassUI
import SwiftUI

/// The Nearby tab: a placeholder until the Nearby task fills it with the departures around you. It already asks for
/// the location the way that screen will, and shows the friendly state when Express may not use it.
struct NearbyView: View {
    @Environment(AppRouter.self) private var router
    @Environment(LocationService.self) private var location

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.nearbyPath) {
            content
                .navigationTitle("Nearby")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch location.authorization {
        case .notDetermined:
            ContentUnavailableView {
                Label("Departures Near You", systemImage: "location.magnifyingglass")
            } description: {
                Text("Share your location to see the stops around you and when the next trains and buses leave.")
            } actions: {
                Button("Use My Location") {
                    location.requestLocation()
                }
                .buttonStyle(.glassProminent)
            }
        case .denied, .restricted:
            LocationDeniedView(authorization: location.authorization)
        case .authorized:
            ContentUnavailableView(
                "Departures Near You",
                systemImage: "tram.fill",
                description: Text("Live departures from the stops around you will appear here.")
            )
        }
    }
}

#Preview("Not asked") {
    NearbyView()
        .environment(AppRouter(selectedTab: .nearby))
        .environment(LocationService(fixed: .notDetermined))
}

#Preview("Denied") {
    NearbyView()
        .environment(AppRouter(selectedTab: .nearby))
        .environment(LocationService(fixed: .denied))
}
