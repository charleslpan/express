extension AppRouter {
    /// Shows a trip, such as a train tapped on the map: pushes its trip view onto ``homePath`` and raises the sheet
    /// (``showTrip(_:)``).
    func showTrip(id: String) {
        showTrip(TripRoute(tripId: id))
    }
}
