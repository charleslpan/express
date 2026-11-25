import GlassUI
import SwiftUI
import TransitKit
import UIKit

/// The map home, the app's one screen: the map full screen, centred on the user where they're in New York and on New
/// York otherwise, with glass controls floating at the top (About, a compass while the map is rotated, and "Show my
/// location"), and the ``HomeSheet`` over it all, which can't be dismissed and leaves the map usable up to half
/// height.
///
/// The home map shows no vehicles. The journey or trip the sheet is showing draws its own vehicle, and only that one
/// (``AppRouter/mapVehicles``, ``SwiftUI/View/rideVehicles(owner:targets:)``).
struct GoView: View {
    @Environment(AppRouter.self) private var router
    @Environment(LocationService.self) private var location

    @State private var camera: MapCamera
    @State private var tilesRendered = false
    /// Whether the map should move to the next location fix, after "Show my location" asked for one.
    @State private var centersOnNextFix = false
    @State private var showsLocationOff = false
    /// Whether the map has moved to the user's first location fix in New York, which it does once.
    @State private var hasCenteredOnUser = false
    /// How tall the sheet's peek is, as the sheet measured it; nil for the search field alone.
    @State private var peekHeight: CGFloat?
    /// The map's frame on screen, and the top edge of the home sheet as it was last measured (both in window
    /// coordinates), which together say how much of the map the sheet covers.
    @State private var mapFrame: CGRect = .zero
    @State private var sheetTop: CGFloat?
    /// How far up from the map's bottom edge the sheet reached the last time it held still.
    @State private var obscuredBottom: CGFloat = 0
    /// Whether the map keeps the picked place's pin in the clear part of the map as the sheet's size settles: from
    /// picking the place until the user moves the map, or journeys or a trip take the camera.
    @State private var framesPlace = false
    /// Counts down the quiet time after the sheet last moved; it ends by taking the sheet's top edge as settled.
    @State private var settleTask: Task<Void, Never>?
    @Namespace private var glass

    /// - Parameter camera: Where the map first looks; New York unless the screenshot harness asks for somewhere else.
    init(camera: MapCamera = .newYork) {
        _camera = State(initialValue: camera)
    }

    var body: some View {
        MapView(
            camera: $camera,
            showsUserLocation: location.isLive && location.authorization == .authorized,
            polylines: router.mapTrip.map { [$0.line] } ?? [],
            pin: placePin,
            route: router.selectedJourney.map { MapRoute(journey: $0, focusedLegs: router.focusedJourneyLegs) },
            vehicles: router.mapVehicles,
            vehicleMoveDuration: RideVehicles.tick / .seconds(1),
            onTilesRendered: { tilesRendered = true },
            onUserGesture: { framesPlace = false }
        )
        .ignoresSafeArea()
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            mapFrame = frame
            scheduleSettle()
        }
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
            } else {
                framesPlace = false
            }
        }
        // A trip opened in the sheet: look at its vehicle, above the sheet, as its line appears.
        .onChange(of: router.mapTrip?.line.id) { _, id in
            if id != nil, let focus = router.mapTrip?.focus {
                hasCenteredOnUser = true
                camera = .following(focus)
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
        HomeSheet(peekHeight: $peekHeight)
            // The sheet's real top edge, whatever its detent or its content's height (the place card fits its
            // text, which Dynamic Type changes); it moves through every height on its way, so it's only used once
            // it holds still (``sheetSettled()``).
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { top in
                sheetTop = top
                scheduleSettle()
            }
            .presentationDetents(
                Set(HomeSheetDetent.allCases.map { $0.presentationDetent(peekHeight: peekHeight) }),
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
            router.homeDetent.presentationDetent(peekHeight: peekHeight)
        } set: { detent in
            router.homeDetent = HomeSheetDetent(detent)
        }
    }

    /// The button column at the top, at the trailing edge.
    private var topControls: some View {
        controls
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
        // ... and for the map to have framed a picked place in the clear part of the map.
        .accessibilityIdentifier(tilesRendered && settleTask == nil ? "map.settled" : "map.loading")
    }

    /// Whether the map is turned away from north, when the compass shows (as in Apple Maps).
    private var isRotated: Bool {
        let bearing = camera.bearing.truncatingRemainder(dividingBy: 360)
        return abs(bearing) > 0.5 && abs(bearing) < 359.5
    }

    /// The picked place's pin, while there is one.
    private var placePin: MapMarker? {
        router.selectedPlace.map { MapMarker(id: $0.placeID, coordinate: $0.coordinate, title: $0.name, color: .red) }
    }

    /// How long the sheet must hold still before the map takes its size as settled: past the sheet's slide between
    /// detents and its card's first measurement.
    private static let settleDelay = Duration.milliseconds(250)
    /// The least of the map that must stay clear for the map to frame a pin in it; with the sheet pulled higher the
    /// pin is under it whatever the map does.
    private static let minimumClearHeight: CGFloat = 160

    /// Looks at a picked place, close enough to see the streets around it, with its pin in the middle of the part of
    /// the map the sheet leaves clear. The sheet is still sliding or measuring its card at this point, so this frames
    /// for where it last settled, and ``sheetSettled()`` frames again for where it ends up.
    private func center(on place: PlaceDetails) {
        hasCenteredOnUser = true
        framesPlace = true
        camera = .framing(place.coordinate, zoom: Self.placeZoom, obscuredBottom: obscuredBottom)
        scheduleSettle()
    }

    private static let placeZoom: Float = 16

    /// Waits for the sheet (and the map's own size) to hold still before ``sheetSettled()``, starting over whenever
    /// either moves.
    private func scheduleSettle() {
        settleTask?.cancel()
        settleTask = Task { @MainActor in
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled else { return }
            sheetSettled()
        }
    }

    /// The sheet's top edge holds still: records how much of the map it covers and, while a picked place is framed,
    /// frames its pin in what's left. Leaves the camera alone once the user has moved the map, while journeys or a
    /// trip have it, and where the sheet covers nearly all of the map.
    private func sheetSettled() {
        settleTask = nil
        guard let sheetTop, mapFrame.height > 0 else { return }
        obscuredBottom = min(max(mapFrame.maxY - sheetTop, 0), mapFrame.height)
        guard framesPlace, let place = router.selectedPlace,
              router.homePath.isEmpty, router.selectedJourney == nil, router.mapTrip == nil,
              mapFrame.height - obscuredBottom >= Self.minimumClearHeight
        else { return }
        camera = .framing(place.coordinate, zoom: Self.placeZoom, obscuredBottom: obscuredBottom)
    }

    /// Moves the map to the user's first fix in New York; outside it the map stays on the city.
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
        .environment(AppEnvironment())
}
