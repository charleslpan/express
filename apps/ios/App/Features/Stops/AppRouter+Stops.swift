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
