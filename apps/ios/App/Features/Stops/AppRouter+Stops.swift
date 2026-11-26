import Foundation
import SwiftUI
import TransitKit

/// A stop's full departures board, pushed onto the home sheet's stack (``StopDetailView``).
struct StopRoute: Hashable {
    /// The id to ask for the stop's departures by: a subway station's id lists its whole complex.
    var stopId: String
    /// The stop's name as riders read it, shown while its departures load.
    var name: String
    var isSubway: Bool
}

/// One vehicle's trip, pushed onto the home sheet's stack (``TripView``).
struct TripRoute: Hashable {
    var tripId: String
    /// The station the trip was opened from, such as the stop whose board it was tapped on, which the trip's stop
    /// list marks; `nil` from the map.
    var stationId: String?
}

/// A trip drawn on the map while its ``TripView`` shows: its track in the line's colour, and where the map should
/// look when it first appears.
struct MapTrip: Equatable {
    var line: MapPolyline
    /// The vehicle, or the trip's first stop before it sets off.
    var focus: Coordinate
}

extension AppRouter {
    /// Opens a stop's full departures board, from a tap on a Nearby stop: pushes it onto ``homePath`` and raises the
    /// sheet to half height so the board shows.
    func showStop(_ route: StopRoute) {
        homePath.append(route)
        raiseForDetail()
    }

    /// Opens a vehicle's trip, from a tap on a departure or on a vehicle on the map: pushes it onto ``homePath`` and
    /// raises the sheet to half height, leaving the map above it free to show the trip's line.
    func showTrip(_ route: TripRoute) {
        homePath.append(route)
        raiseForDetail()
    }

    /// Draws a trip on the map, or clears it with `nil`.
    func showOnMap(_ trip: MapTrip?) {
        if trip != mapTrip {
            mapTrip = trip
        }
    }

    /// Clears the trip on the map, if it's the one with this id; a newer trip pushed over it stays.
    func hideOnMap(tripId: String) {
        if mapTrip?.line.id == tripId {
            mapTrip = nil
        }
    }

    /// Detail needs more room than the peek gives; half height leaves the map usable above it.
    private func raiseForDetail() {
        if homeDetent == .peek {
            homeDetent = .half
        }
    }
}

extension StopRoute {
    /// The board for a stop near the rider.
    init(_ stop: NearbyStop) {
        self.init(stopId: stop.id, name: stop.displayName, isSubway: stop.isSubway)
    }
}

extension MapCamera {
    /// Where the map looks to follow a vehicle with the home sheet at half height: zoomed in far enough that live
    /// trains show (``TrainVisibility``), with the vehicle in the middle of the map left above the sheet rather than
    /// under it.
    static func following(_ coordinate: Coordinate, zoom: Float = 14.5) -> MapCamera {
        // About a quarter of an iPhone's height (852 pt), in metres at this zoom (Web Mercator's metres per point).
        let metresPerPoint = 156_543.033_92 * cos(coordinate.latitude * .pi / 180) / pow(2, Double(zoom))
        let offset = 852 * 0.25 * metresPerPoint / 111_320
        return MapCamera(
            center: Coordinate(latitude: coordinate.latitude - offset, longitude: coordinate.longitude),
            zoom: zoom
        )
    }
}

extension MapCamera {
    /// Where the map looks to show `coordinate` in the middle of the part of the map the home sheet leaves clear,
    /// rather than in the middle of the whole map, which the sheet covers.
    ///
    /// The map is centred on the middle of its whole view, so a pin in the middle of a map with the sheet over its
    /// lower part is under the sheet. Looking at a point below the pin by half the covered height puts the pin in the
    /// middle of what's left: the camera shifts by `obscuredBottom / 2` points (`obscuredTop` pulls the other way).
    /// Both are measured in points on screen, so the result is independent of the screen's size, the sheet's detent,
    /// and Dynamic Type: callers pass what the sheet covers right now (``GoView``).
    ///
    /// The map isn't rotated by this: it looks north, the way picking a place does.
    ///
    /// - Parameters:
    ///   - zoom: A Google zoom level; it sets how many metres a point on screen is.
    ///   - obscuredBottom: How far up from the map's bottom edge the sheet reaches, in points; 0 for none.
    ///   - obscuredTop: How far down from the map's top edge something covers it, in points; 0 for none.
    static func framing(
        _ coordinate: Coordinate,
        zoom: Float,
        obscuredBottom: CGFloat,
        obscuredTop: CGFloat = 0
    ) -> MapCamera {
        let shift = max(obscuredBottom, 0) / 2 - max(obscuredTop, 0) / 2
        guard shift != 0 else {
            return MapCamera(center: coordinate, zoom: zoom)
        }
        // Web Mercator: Google's world is 256 points across at zoom 0 and doubles with every level. Screen-down is
        // south, which is less Mercator y.
        let pointsPerRadian = 256 * pow(2, Double(zoom)) / (2 * .pi)
        let latitude = coordinate.latitude * .pi / 180
        let y = log(tan(.pi / 4 + latitude / 2)) - Double(shift) / pointsPerRadian
        let shifted = (2 * atan(exp(y)) - .pi / 2) * 180 / .pi
        return MapCamera(center: Coordinate(latitude: shifted, longitude: coordinate.longitude), zoom: zoom)
    }
}

extension View {
    /// Registers the stop and trip screens in a navigation stack, for ``AppRouter/showStop(_:)`` and
    /// ``AppRouter/showTrip(_:)`` to push.
    func stopsNavigationDestinations() -> some View {
        navigationDestination(for: StopRoute.self) { route in
            StopDetailView(route: route)
        }
        .navigationDestination(for: TripRoute.self) { route in
            TripView(route: route)
        }
    }
}
