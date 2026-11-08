import GlassUI
import SwiftUI
import TransitKit
import UIKit

/// The map home, the app's one screen: the map full screen, centred on the user where they're in New York and on New
/// York otherwise, with glass controls floating at the top (About, a compass while the map is rotated, and "Show my
/// location"), a banner while the user is outside the area Express serves, live subway trains (``LiveTrains``) with a
/// notice while their positions may not be real time, and the ``HomeSheet`` over it all, which can't be dismissed and
/// leaves the map usable up to half height.
struct GoView: View {
    @Environment(AppRouter.self) private var router
    @Environment(LocationService.self) private var location

    @State private var camera: MapCamera
    @State private var trains = LiveTrains()
    @State private var tilesRendered = false
    /// Whether the map should move to the next location fix, after "Show my location" asked for one.
    @State private var centersOnNextFix = false
    @State private var showsLocationOff = false
    /// Whether the map has moved to the user's first location fix in New York, which it does once.
    @State private var hasCenteredOnUser = false
    @Namespace private var glass

    /// - Parameter camera: Where the map first looks; New York unless the screenshot harness asks for somewhere else.
    init(camera: MapCamera = .newYork) {
        _camera = State(initialValue: camera)
    }

    var body: some View {
        MapView(
            camera: $camera,
            showsUserLocation: location.isLive && location.authorization == .authorized,
            pin: placePin,
            vehicles: trains.vehicles,
            vehicleMoveDuration: LiveTrains.tick / .seconds(1),
            onTilesRendered: { tilesRendered = true },
            onCameraIdle: { trains.cameraDidIdle($0) },
            onCameraMove: { trains.cameraDidMove() },
            onVehicleTap: { router.showTrip(id: $0) }
        )
        .ignoresSafeArea()
        .liveTrains(trains)
        // The controls sit at the top, clear of the sheet at its peek.
        .overlay(alignment: .top) {
            topControls
                .padding(Spacing.floatingInset)
        }
        .sheet(isPresented: .constant(true)) {
            homeSheet
        }
        .onAppear {
            // Already allowed: start updates, which asks nothing. Otherwise wait for "Show my location".
            if location.authorization == .authorized {
                location.requestLocation()
            }
            if let place = router.selectedPlace {
                center(on: place)
            } else {
                centerOnUserInNewYork(location.location)
            }
        }
        .onChange(of: router.selectedPlace) { _, place in
            if let place {
                center(on: place)
            }
        }
        .onChange(of: location.location) { _, fix in
            guard let fix else { return }
            if centersOnNextFix {
                centersOnNextFix = false
                hasCenteredOnUser = true
                camera = MapCamera(center: fix, zoom: 16)
            } else {
                centerOnUserInNewYork(fix)
            }
        }
    }

    private var homeSheet: some View {
        HomeSheet()
            .presentationDetents(
                Set(HomeSheetDetent.allCases.map(\.presentationDetent)),
                selection: detent
            )
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled()
            // The map is covered by the sheet, so an alert from the map's buttons presents from the sheet.
            .alert("Location Is Off", isPresented: $showsLocationOff) {
                if location.authorization == .denied,
                   let settings = URL(string: UIApplication.openSettingsURLString)
                {
                    Link("Open Settings", destination: settings)
                }
                Button("Not Now", role: .cancel) {}
            } message: {
                Text("Turn on Location Services for Express in Settings to see where you are on the map.")
            }
    }

    /// The sheet's detent, through ``AppRouter/homeDetent`` so features can raise and lower it.
    private var detent: Binding<PresentationDetent> {
        Binding {
            router.homeDetent.presentationDetent
        } set: { detent in
            router.homeDetent = HomeSheetDetent(detent)
        }
    }

    /// The banner (when it shows) across the top, with the button column under it at the trailing edge, so the
    /// two never overlap at any text size.
    private var topControls: some View {
        VStack(alignment: .trailing, spacing: Spacing.floatingInset) {
            if isOutsideServiceArea {
                OutsideServiceAreaBanner()
            }
            if trains.mayNotBeRealTime {
                LiveTrainsNotice()
            }
            controls
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var controls: some View {
        GlassEffectContainer(spacing: Spacing.floatingInset) {
            VStack(spacing: Spacing.floatingInset) {
                GlassIconButton("About Express", systemImage: "info") {
                    router.showAbout()
                }
                .glassEffectID("about", in: glass)
                if isRotated {
                    GlassIconButton("Point the map north", systemImage: "location.north.line.fill") {
                        camera.bearing = 0
                    }
                    .rotationEffect(.degrees(-camera.bearing))
                    .accessibilityValue("Facing \(Int(camera.bearing.rounded())) degrees")
                    .glassEffectID("compass", in: glass)
                }
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

    /// Whether the map is turned away from north, when the compass shows (as in Apple Maps).
    private var isRotated: Bool {
        let bearing = camera.bearing.truncatingRemainder(dividingBy: 360)
        return abs(bearing) > 0.5 && abs(bearing) < 359.5
    }

    /// Whether the user is somewhere Express doesn't serve yet; false while their location is unknown.
    private var isOutsideServiceArea: Bool {
        guard location.authorization == .authorized, let fix = location.location else { return false }
        return !ServiceArea.nyc.contains(fix)
    }

    /// The picked place's pin, while there is one.
    private var placePin: MapMarker? {
        router.selectedPlace.map { MapMarker(id: $0.placeID, coordinate: $0.coordinate, title: $0.name, color: .red) }
    }

    /// Centres the map on a picked place, close enough to see the streets around it.
    private func center(on place: PlaceDetails) {
        hasCenteredOnUser = true
        camera = MapCamera(center: place.coordinate, zoom: 16)
    }

    /// Moves the map to the user's first fix in New York; outside it the map stays on the city, under the banner.
    private func centerOnUserInNewYork(_ fix: Coordinate?) {
        guard !hasCenteredOnUser, let fix, ServiceArea.nyc.contains(fix) else { return }
        hasCenteredOnUser = true
        camera = MapCamera(center: fix, zoom: 15)
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
        .environment(AppEnvironment())
        .environment(AppRouter())
        .environment(LocationService(fixed: .notDetermined))
}
