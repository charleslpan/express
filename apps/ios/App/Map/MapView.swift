import CoreLocation
import GoogleMaps
import SwiftUI
import TransitKit

/// Where the map looks: a center, a Google zoom level (0 is the world, about 13 a neighborhood, 18 a block), and a
/// bearing in degrees clockwise from north, which rotating the map with two fingers changes.
struct MapCamera: Equatable {
    var center: Coordinate
    var zoom: Float
    var bearing: Double = 0

    /// Lower Manhattan to Downtown Brooklyn.
    static let newYork = MapCamera(center: Coordinate(latitude: 40.7128, longitude: -74.0060), zoom: 12.5)
}

/// A line drawn on the map, such as a route leg.
struct MapPolyline: Identifiable, Equatable {
    var id: String
    var coordinates: [Coordinate]
    var color: Color
    var width: CGFloat = 5
}

/// A pin on the map, such as a stop.
struct MapMarker: Identifiable, Equatable {
    var id: String
    var coordinate: Coordinate
    /// Shown in the marker's info window and read by VoiceOver.
    var title: String
    var color: Color = .accentColor
}

/// A vehicle moving on the map, such as a subway train at its estimated position: a line bullet, with an arrow
/// pointing the way it's heading.
struct MapVehicle: Identifiable, Equatable {
    var id: String
    var coordinate: Coordinate
    /// The direction of travel, in degrees clockwise from north.
    var bearing: Double
    var bullet: LineBullet
    /// What VoiceOver reads, such as "Q train to 14 St-Union Sq".
    var accessibilityLabel: String
}

/// What the map shows once it settles: the area on screen and the zoom level.
struct MapViewport: Equatable {
    var bounds: CoordinateBounds
    var zoom: Double
}

/// Express's Google map, the one map view every map screen builds on.
///
/// Google offers no SwiftUI map, so this wraps `GMSMapView`. It styles itself with ``MapStyle`` for the current
/// color scheme (JSON styles, never a billed map ID) and shows "Map unavailable" where the build has no API key
/// (``GoogleMapsServices``). Overlay controls with Liquid Glass on top of it; it ignores safe areas only where the
/// caller asks.
struct MapView: View {
    /// Where the map looks. Updating it moves the map; panning and zooming write it back once the map settles.
    @Binding var camera: MapCamera
    /// Whether to show the blue user-location dot. The app must already have location permission.
    var showsUserLocation = false
    var polylines: [MapPolyline] = []
    var markers: [MapMarker] = []
    /// Vehicles to show. A vehicle that moves glides to its new place over ``vehicleMoveDuration``.
    var vehicles: [MapVehicle] = []
    /// How long a vehicle takes to glide to a new position, such as the time until the next one; 0 jumps.
    var vehicleMoveDuration: TimeInterval = 0
    /// Called once the visible tiles have finished rendering, such as for the screenshot harness to wait on.
    var onTilesRendered: (() -> Void)?
    /// Called whenever the map comes to rest after loading or moving, with the area it shows.
    var onCameraIdle: (@MainActor (MapViewport) -> Void)?
    /// Called as the map starts to move, by a gesture or an animation.
    var onCameraMove: (@MainActor () -> Void)?
    /// Called with a vehicle's id when it's tapped.
    var onVehicleTap: (@MainActor (String) -> Void)?

    var body: some View {
        if GoogleMapsServices.isConfigured {
            GoogleMapRepresentable(
                camera: $camera,
                showsUserLocation: showsUserLocation,
                polylines: polylines,
                markers: markers,
                vehicles: vehicles,
                vehicleMoveDuration: vehicleMoveDuration,
                onTilesRendered: onTilesRendered,
                onCameraIdle: onCameraIdle,
                onCameraMove: onCameraMove,
                onVehicleTap: onVehicleTap
            )
            .accessibilityLabel("Map")
        } else {
            ContentUnavailableView(
                "Map Unavailable",
                systemImage: "map",
                description: Text("This build of Express has no Google Maps key.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .secondarySystemBackground))
            .onAppear { onTilesRendered?() }
        }
    }
}

private struct GoogleMapRepresentable: UIViewRepresentable {
    @Binding var camera: MapCamera
    var showsUserLocation: Bool
    var polylines: [MapPolyline]
    var markers: [MapMarker]
    var vehicles: [MapVehicle]
    var vehicleMoveDuration: TimeInterval
    var onTilesRendered: (() -> Void)?
    var onCameraIdle: (@MainActor (MapViewport) -> Void)?
    var onCameraMove: (@MainActor () -> Void)?
    var onVehicleTap: (@MainActor (String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(camera: $camera)
    }

    func makeUIView(context: Context) -> GMSMapView {
        let options = GMSMapViewOptions()
        options.camera = cameraPosition(for: camera)
        let mapView = GMSMapView(options: options)
        mapView.delegate = context.coordinator
        mapView.isIndoorEnabled = false
        mapView.isBuildingsEnabled = false
        mapView.isTrafficEnabled = false
        mapView.settings.compassButton = false
        mapView.settings.myLocationButton = false
        mapView.settings.tiltGestures = false
        context.coordinator.shownCamera = camera
        return mapView
    }

    func updateUIView(_ mapView: GMSMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.camera = $camera
        coordinator.onTilesRendered = onTilesRendered
        coordinator.onCameraIdle = onCameraIdle
        coordinator.onCameraMove = onCameraMove
        coordinator.onVehicleTap = onVehicleTap

        let colorScheme = context.environment.colorScheme
        if coordinator.colorScheme != colorScheme {
            coordinator.colorScheme = colorScheme
            mapView.mapStyle = MapStyle.style(for: colorScheme)
        }
        if mapView.isMyLocationEnabled != showsUserLocation {
            mapView.isMyLocationEnabled = showsUserLocation
        }
        if coordinator.shownCamera != camera {
            coordinator.shownCamera = camera
            let position = cameraPosition(for: camera)
            if context.transaction.disablesAnimations || !UIView.areAnimationsEnabled {
                mapView.camera = position
            } else {
                mapView.animate(to: position)
            }
        }
        coordinator.show(polylines: polylines, on: mapView)
        coordinator.show(markers: markers, on: mapView)
        let moveDuration = context.transaction.disablesAnimations || !UIView.areAnimationsEnabled
            ? 0 : vehicleMoveDuration
        coordinator.show(vehicles: vehicles, colorScheme: colorScheme, moveDuration: moveDuration, on: mapView)
    }

    @MainActor
    final class Coordinator: NSObject {
        var camera: Binding<MapCamera>
        /// The camera the map is at or moving to, so updates neither re-animate it nor echo it back.
        var shownCamera: MapCamera?
        var colorScheme: ColorScheme?
        var onTilesRendered: (() -> Void)?
        var onCameraIdle: (@MainActor (MapViewport) -> Void)?
        var onCameraMove: (@MainActor () -> Void)?
        var onVehicleTap: (@MainActor (String) -> Void)?
        private var polylines: [MapPolyline] = []
        private var markers: [MapMarker] = []
        private var overlays: [GMSOverlay] = []
        private var pins: [GMSMarker] = []
        private var vehicles: [MapVehicle] = []
        private var vehicleColorScheme: ColorScheme?
        /// Each vehicle's bullet, and the flat arrow under it that turns with its bearing, by the vehicle's id.
        private var vehicleMarkers: [String: (bullet: GMSMarker, arrow: GMSMarker)] = [:]

        init(camera: Binding<MapCamera>) {
            self.camera = camera
        }

        func show(polylines: [MapPolyline], on mapView: GMSMapView) {
            guard polylines != self.polylines else { return }
            self.polylines = polylines
            overlays.forEach { $0.map = nil }
            overlays = polylines.map { line in
                let path = GMSMutablePath()
                line.coordinates.forEach { path.add(CLLocationCoordinate2D($0)) }
                let polyline = GMSPolyline(path: path)
                polyline.strokeColor = UIColor(line.color)
                polyline.strokeWidth = line.width
                polyline.map = mapView
                return polyline
            }
        }

        func show(markers: [MapMarker], on mapView: GMSMapView) {
            guard markers != self.markers else { return }
            self.markers = markers
            pins.forEach { $0.map = nil }
            pins = markers.map { marker in
                let pin = GMSMarker(position: CLLocationCoordinate2D(marker.coordinate))
                pin.title = marker.title
                pin.icon = GMSMarker.markerImage(with: UIColor(marker.color))
                pin.map = mapView
                return pin
            }
        }

        /// Adds, moves, and removes vehicle markers to match `vehicles`, gliding moved ones over `moveDuration` with
        /// the SDK's own marker animation (Core Animation on the marker's position and rotation).
        func show(
            vehicles: [MapVehicle],
            colorScheme: ColorScheme,
            moveDuration: TimeInterval,
            on mapView: GMSMapView
        ) {
            let schemeChanged = vehicleColorScheme != colorScheme
            guard vehicles != self.vehicles || schemeChanged else { return }
            let previous = Dictionary(self.vehicles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            self.vehicles = vehicles
            vehicleColorScheme = colorScheme
            // The map's own traits (text size among them), in the appearance SwiftUI asks for.
            let traits = mapView.traitCollection.modifyingTraits {
                $0.userInterfaceStyle = colorScheme == .dark ? .dark : .light
            }

            let current = Set(vehicles.map(\.id))
            for (id, markers) in vehicleMarkers where !current.contains(id) {
                markers.bullet.map = nil
                markers.arrow.map = nil
                vehicleMarkers[id] = nil
            }

            CATransaction.begin()
            CATransaction.setAnimationDuration(moveDuration)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .linear))
            CATransaction.setDisableActions(moveDuration == 0)
            for vehicle in vehicles {
                let position = CLLocationCoordinate2D(vehicle.coordinate)
                guard let markers = vehicleMarkers[vehicle.id] else {
                    vehicleMarkers[vehicle.id] = addMarkers(for: vehicle, traits: traits, on: mapView)
                    continue
                }
                if schemeChanged || previous[vehicle.id]?.bullet != vehicle.bullet {
                    markers.bullet.icon = VehicleMarkerImage.bullet(vehicle.bullet, traits: traits)
                    markers.arrow.icon = VehicleMarkerImage.arrow(vehicle.bullet, traits: traits)
                }
                markers.bullet.title = vehicle.accessibilityLabel
                markers.bullet.position = position
                markers.arrow.position = position
                // Turn the shorter way round, so 350° to 10° is a nudge rather than a spin.
                let turn = (vehicle.bearing - markers.arrow.rotation + 540).truncatingRemainder(dividingBy: 360) - 180
                markers.arrow.rotation += turn
            }
            CATransaction.commit()
        }

        private func addMarkers(
            for vehicle: MapVehicle,
            traits: UITraitCollection,
            on mapView: GMSMapView
        ) -> (bullet: GMSMarker, arrow: GMSMarker) {
            let position = CLLocationCoordinate2D(vehicle.coordinate)
            let arrow = GMSMarker(position: position)
            arrow.icon = VehicleMarkerImage.arrow(vehicle.bullet, traits: traits)
            arrow.groundAnchor = CGPoint(x: 0.5, y: 0.5)
            // Flat, so its rotation is a compass bearing that turns with the map.
            arrow.isFlat = true
            arrow.rotation = vehicle.bearing
            arrow.zIndex = 1
            arrow.userData = vehicle.id
            arrow.map = mapView

            let bullet = GMSMarker(position: position)
            bullet.icon = VehicleMarkerImage.bullet(vehicle.bullet, traits: traits)
            bullet.groundAnchor = CGPoint(x: 0.5, y: 0.5)
            bullet.title = vehicle.accessibilityLabel
            bullet.zIndex = 2
            bullet.userData = vehicle.id
            bullet.map = mapView
            return (bullet, arrow)
        }
    }
}

extension GoogleMapRepresentable.Coordinator: @preconcurrency GMSMapViewDelegate {
    func mapView(_ mapView: GMSMapView, idleAt position: GMSCameraPosition) {
        if let onCameraIdle {
            let region = GMSCoordinateBounds(region: mapView.projection.visibleRegion())
            let bounds = CoordinateBounds(
                southWest: Coordinate(latitude: region.southWest.latitude, longitude: region.southWest.longitude),
                northEast: Coordinate(latitude: region.northEast.latitude, longitude: region.northEast.longitude)
            )
            onCameraIdle(MapViewport(bounds: bounds, zoom: Double(position.zoom)))
        }
        let settled = MapCamera(
            center: Coordinate(latitude: position.target.latitude, longitude: position.target.longitude),
            zoom: position.zoom,
            bearing: position.bearing
        )
        guard settled != shownCamera else { return }
        shownCamera = settled
        camera.wrappedValue = settled
    }

    func mapView(_: GMSMapView, willMove _: Bool) {
        onCameraMove?()
    }

    func mapView(_: GMSMapView, didTap marker: GMSMarker) -> Bool {
        // A vehicle's tap goes to the caller, with no info window; a pin's shows its title as before.
        guard let id = marker.userData as? String, vehicleMarkers[id] != nil else { return false }
        onVehicleTap?(id)
        return true
    }

    func mapViewDidFinishTileRendering(_: GMSMapView) {
        onTilesRendered?()
    }
}

private func cameraPosition(for camera: MapCamera) -> GMSCameraPosition {
    GMSCameraPosition(
        latitude: camera.center.latitude,
        longitude: camera.center.longitude,
        zoom: camera.zoom,
        bearing: camera.bearing,
        viewingAngle: 0
    )
}

private extension CLLocationCoordinate2D {
    init(_ coordinate: Coordinate) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}
