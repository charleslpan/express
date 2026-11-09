import GoogleMaps
import SwiftUI
import TransitKit

/// A journey drawn on the map: each leg a line in its colour, walking legs dashed. The map fits itself to each new
/// route, keeping it clear of the controls at the top and the home sheet at the bottom, and to the segments it focuses
/// on, such as a leg tapped in the journey's plan.
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
    /// The segments the map zooms to, by id; empty for the whole route. A change moves the map to fit them.
    var focusedSegmentIDs: [String] = []
}

/// Draws a ``MapRoute`` on a `GMSMapView` for ``MapView``: its legs as polylines, and the camera fitted to each new
/// route.
@MainActor
final class MapRouteOverlay {
    private var route: MapRoute?
    private var lines: [GMSPolyline] = []

    func show(_ route: MapRoute?, on mapView: GMSMapView, animated: Bool) {
        guard route != self.route else { return }
        let isNew = route?.id != self.route?.id
        let isRefocused = route?.focusedSegmentIDs != self.route?.focusedSegmentIDs
        self.route = route
        lines.forEach { $0.map = nil }
        lines = (route?.segments ?? []).map { segment in
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
        if let route, isNew || isRefocused {
            fit(route, on: mapView, animated: animated)
        }
    }

    /// Moves the map so the route's focused segments (or, with none, the whole route) show between the controls at
    /// the top and the sheet at half height.
    private func fit(_ route: MapRoute, on mapView: GMSMapView, animated: Bool) {
        let focused = route.segments.filter { route.focusedSegmentIDs.contains($0.id) }
        let segments = focused.isEmpty ? route.segments : focused
        let bounds = segments.flatMap(\.coordinates).reduce(GMSCoordinateBounds()) { bounds, coordinate in
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
}
