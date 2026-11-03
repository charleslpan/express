import CoreLocation
import GoogleMaps
import SwiftUI
import TransitKit

/// Where the map looks: a center and a Google zoom level (0 is the world, about 13 a neighborhood, 18 a block).
struct MapCamera: Equatable {
    var center: Coordinate
    var zoom: Float

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
    /// Called once the visible tiles have finished rendering, such as for the screenshot harness to wait on.
    var onTilesRendered: (() -> Void)?

    var body: some View {
        if GoogleMapsServices.isConfigured {
            GoogleMapRepresentable(
                camera: $camera,
                showsUserLocation: showsUserLocation,
                polylines: polylines,
                markers: markers,
                onTilesRendered: onTilesRendered
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
    var onTilesRendered: (() -> Void)?

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
    }

    @MainActor
    final class Coordinator: NSObject {
        var camera: Binding<MapCamera>
        /// The camera the map is at or moving to, so updates neither re-animate it nor echo it back.
        var shownCamera: MapCamera?
        var colorScheme: ColorScheme?
        var onTilesRendered: (() -> Void)?
        private var polylines: [MapPolyline] = []
        private var markers: [MapMarker] = []
        private var overlays: [GMSOverlay] = []
        private var pins: [GMSMarker] = []

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
    }
}

extension GoogleMapRepresentable.Coordinator: @preconcurrency GMSMapViewDelegate {
    func mapView(_: GMSMapView, idleAt position: GMSCameraPosition) {
        let settled = MapCamera(
            center: Coordinate(latitude: position.target.latitude, longitude: position.target.longitude),
            zoom: position.zoom
        )
        guard settled != shownCamera else { return }
        shownCamera = settled
        camera.wrappedValue = settled
    }

    func mapViewDidFinishTileRendering(_: GMSMapView) {
        onTilesRendered?()
    }
}

private func cameraPosition(for camera: MapCamera) -> GMSCameraPosition {
    GMSCameraPosition(latitude: camera.center.latitude, longitude: camera.center.longitude, zoom: camera.zoom)
}

private extension CLLocationCoordinate2D {
    init(_ coordinate: Coordinate) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}
