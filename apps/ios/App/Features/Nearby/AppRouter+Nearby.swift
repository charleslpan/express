import TransitKit

extension AppRouter {
    /// Opens a line's departures from a nearby stop, from a tap on its row in the Nearby section: the stop's full
    /// board, with every line and direction (``showStop(_:)``).
    func showDepartures(_: LineDepartures, at stop: NearbyStop) {
        showStop(StopRoute(stop))
    }

    /// Opens a nearby stop's full board, from a tap on its name in the Nearby section.
    func showStop(_ stop: NearbyStop) {
        showStop(StopRoute(stop))
    }
}
