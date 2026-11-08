import TransitKit

extension AppRouter {
    /// Opens a line's departures from a nearby stop, from a tap on its row in the Nearby section.
    ///
    /// The stop detail and trip view (N2) will push them onto ``homePath`` and raise the sheet; until then this does
    /// nothing.
    func showDepartures(_: LineDepartures, at _: NearbyStop) {}
}
