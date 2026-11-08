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

/// A journey drawn on the map: each leg a line in its colour, walking legs dashed. The map fits itself to each new
/// route, keeping it clear of the controls at the top and the home sheet at the bottom.
struct MapRoute: Identifiable, Equatable {
    /// One leg of the route.
    struct Segment: Identifiable, Equatable {
        var id: String
        var coordinates: [Coordinate]
        var color: Color
        /// Whether the line is dashed, as for a walk.
        var isDashed = false
    }

    /// Picks out the route: a new id moves the map to fit it, while the same id with new segments (a refresh)
    /// leaves the map where it is.
    var id: String
    var segments: [Segment]
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
    /// The one place the user picked, such as a search result: drawn above every other marker.
    var pin: MapMarker?
    /// The journey to draw, such as the selected journey option: above ``polylines``, below every marker.
    var route: MapRoute?
    /// Called once the visible tiles have finished rendering, such as for the screenshot harness to wait on.
    var onTilesRendered: (() -> Void)?

    var body: some View {
        if GoogleMapsServices.isConfigured {
            GoogleMapRepresentable(
                camera: $camera,
                showsUserLocation: showsUserLocation,
                polylines: polylines,
                markers: markers,
                pin: pin,
                route: route,
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
    var pin: MapMarker?
    var route: MapRoute?
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
        let animated = !context.transaction.disablesAnimations && UIView.areAnimationsEnabled
        if coordinator.shownCamera != camera {
            coordinator.shownCamera = camera
            let position = cameraPosition(for: camera)
            if animated {
                mapView.animate(to: position)
            } else {
                mapView.camera = position
            }
        }
        coordinator.show(polylines: polylines, on: mapView)
        coordinator.show(route: route, on: mapView, animated: animated)
        coordinator.show(markers: markers, on: mapView)
        coordinator.show(pin: pin, on: mapView)
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
        private var pin: MapMarker?
        private var pinMarker: GMSMarker?
        private var route: MapRoute?
        private var routeLines: [GMSPolyline] = []

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

        func show(route: MapRoute?, on mapView: GMSMapView, animated: Bool) {
            guard route != self.route else { return }
            let isNew = route?.id != self.route?.id
            self.route = route
            routeLines.forEach { $0.map = nil }
            routeLines = (route?.segments ?? []).map { segment in
                let path = GMSMutablePath()
                segment.coordinates.forEach { path.add(CLLocationCoordinate2D($0)) }
                let line = GMSPolyline(path: path)
                let color = UIColor(segment.color)
                if segment.isDashed {
                    line.strokeWidth = 4
                    // Dashes in metres along the path: short enough to read as a walk from a street to the city.
                    line.spans = GMSStyleSpans(
                        path,
                        [GMSStrokeStyle.solidColor(color), GMSStrokeStyle.solidColor(.clear)],
                        [12, 8],
                        .rhumb
                    )
                } else {
                    line.strokeWidth = 6
                    line.strokeColor = color
                }
                line.zIndex = 1
                line.map = mapView
                return line
            }
            if let route, isNew {
                fit(route, on: mapView, animated: animated)
            }
        }

        /// Moves the map so the whole route shows between the controls at the top and the sheet at half height.
        private func fit(_ route: MapRoute, on mapView: GMSMapView, animated: Bool) {
            let bounds = route.segments.flatMap(\.coordinates).reduce(GMSCoordinateBounds()) { bounds, coordinate in
                bounds.includingCoordinate(CLLocationCoordinate2D(coordinate))
            }
            guard bounds.isValid else { return }
            // On the next turn of the run loop, once the map has its size.
            Task { @MainActor [weak mapView] in
                guard let mapView else { return }
                let insets = UIEdgeInsets(
                    top: 120,
                    left: 48,
                    bottom: mapView.bounds.height / 2 + 32,
                    right: 80
                )
                let update = GMSCameraUpdate.fit(bounds, with: insets)
                if animated {
                    mapView.animate(with: update)
                } else {
                    mapView.moveCamera(update)
                }
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

        func show(pin: MapMarker?, on mapView: GMSMapView) {
            guard pin != self.pin else { return }
            self.pin = pin
            pinMarker?.map = nil
            pinMarker = pin.map { pin in
                let marker = GMSMarker(position: CLLocationCoordinate2D(pin.coordinate))
                marker.title = pin.title
                marker.icon = GMSMarker.markerImage(with: UIColor(pin.color))
                marker.zIndex = 1
                marker.map = mapView
                return marker
            }
        }
    }
}

extension GoogleMapRepresentable.Coordinator: @preconcurrency GMSMapViewDelegate {
    func mapView(_: GMSMapView, idleAt position: GMSCameraPosition) {
        let settled = MapCamera(
            center: Coordinate(latitude: position.target.latitude, longitude: position.target.longitude),
            zoom: position.zoom,
            bearing: position.bearing
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
