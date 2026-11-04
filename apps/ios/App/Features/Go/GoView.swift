import GlassUI
import SwiftUI
import UIKit

/// The Go tab: the map, full screen under the tab bar, with glass controls floating over it. S2 builds the home
/// sheet and the rest of the map home on top of this.
struct GoView: View {
    @Environment(AppRouter.self) private var router
    @Environment(LocationService.self) private var location

    @State private var camera = MapCamera.newYork
    @State private var tilesRendered = false
    /// Whether the map should move to the next location fix, after "Show my location" asked for one.
    @State private var centersOnNextFix = false
    @State private var showsLocationOff = false
    @Namespace private var glass

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.goPath) {
            MapView(
                camera: $camera,
                showsUserLocation: location.authorization == .authorized,
                onTilesRendered: { tilesRendered = true }
            )
            .ignoresSafeArea()
            .overlay(alignment: .topTrailing) {
                controls
                    .padding(Spacing.floatingInset)
            }
            .toolbarVisibility(.hidden, for: .navigationBar)
        }
        .onChange(of: location.location) { _, fix in
            guard centersOnNextFix, let fix else { return }
            centersOnNextFix = false
            camera = MapCamera(center: fix, zoom: 16)
        }
        .alert("Location Is Off", isPresented: $showsLocationOff) {
            if location.authorization == .denied, let settings = URL(string: UIApplication.openSettingsURLString) {
                Link("Open Settings", destination: settings)
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("Turn on Location Services for Express in Settings to see where you are on the map.")
        }
    }

    private var controls: some View {
        GlassEffectContainer(spacing: Spacing.floatingInset) {
            VStack(spacing: Spacing.floatingInset) {
                GlassIconButton("About Express", systemImage: "info") {
                    router.showAbout()
                }
                .glassEffectID("about", in: glass)
                GlassIconButton("Show my location", systemImage: locationSymbol) {
                    showMyLocation()
                }
                .glassEffectID("location", in: glass)
            }
        }
        // The screenshot harness waits for the map's tiles before it captures.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(tilesRendered ? "map.settled" : "map.loading")
    }

    private var locationSymbol: String {
        switch location.authorization {
        case .denied, .restricted: "location.slash"
        case .notDetermined, .authorized: "location"
        }
    }

    private func showMyLocation() {
        switch location.authorization {
        case .denied, .restricted:
            showsLocationOff = true
        case .authorized:
            if let fix = location.location {
                camera = MapCamera(center: fix, zoom: 16)
            } else {
                centersOnNextFix = true
            }
            location.requestLocation()
        case .notDetermined:
            centersOnNextFix = true
            location.requestLocation()
        }
    }
}

#Preview {
    GoView()
        .environment(AppRouter())
        .environment(LocationService(fixed: .notDetermined))
}
