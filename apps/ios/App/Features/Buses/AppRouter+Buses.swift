import TransitKit

extension AppRouter {
    /// Shows a bus tapped on the map: its trip, looked up by ``Bus/tripId`` (the headsign comes from MOTIS's
    /// `/api/v6/trip`), pushed onto ``homePath`` with the sheet raised (``showTrip(_:)``). A bus Bus Time gives no
    /// trip for opens nothing.
    func showBus(_ bus: Bus) {
        guard let tripId = bus.tripId, !tripId.isEmpty else { return }
        showTrip(TripRoute(tripId: tripId))
    }
}
