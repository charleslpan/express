import TransitKit

/// The journey options screen's place in the home sheet's navigation stack: the journey it starts with.
struct JourneyOptionsRoute: Hashable {
    var query: JourneyQuery
}

extension AppRouter {
    /// Shows ways to get to `place` from the current location, leaving now: pushes the journey options onto the home
    /// sheet's stack, over the place's card, at half height.
    func showJourneys(to place: PlaceDetails) {
        showJourneys(JourneyQuery(to: .place(place)))
    }

    /// Shows the options for `query`.
    func showJourneys(_ query: JourneyQuery) {
        selectedJourney = nil
        homePath.append(JourneyOptionsRoute(query: query))
        homeDetent = .half
    }

    /// Leaves the journey options for the place's card, taking the route off the map.
    func closeJourneys() {
        selectedJourney = nil
        if !homePath.isEmpty {
            homePath.removeLast()
        }
        homeDetent = .half
    }

    /// Shows one journey option, which the rider tapped: for now it selects the option, drawing its route on the map.
    ///
    /// Journey detail (J2) fills this in, pushing the journey's legs and stops onto ``AppRouter/homePath``.
    func showJourneyDetail(_ itinerary: Itinerary) {
        selectedJourney = itinerary
    }
}
