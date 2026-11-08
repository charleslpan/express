import TransitKit

extension AppRouter {
    /// Shows a bus tapped on the map: its trip, with the bus on it.
    ///
    /// A stub until the trip view (N2) lands: N2 fills it in, looking the trip up by ``Bus/tripId`` (the headsign
    /// comes from MOTIS's `/api/v6/trip`), pushing it onto ``homePath``, and raising the sheet.
    func showBus(_: Bus) {}
}
