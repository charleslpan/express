import TransitKit

/// The journey options screen's place in the home sheet's navigation stack: the journey it starts with.
struct JourneyOptionsRoute: Hashable {
    var query: JourneyQuery
}

/// The journey detail screen's place in the home sheet's navigation stack: the journey option tapped, and the name of
/// where it ends, for the last walk (MOTIS names the journey's own ends `START` and `END`).
struct JourneyDetailRoute: Hashable {
    var itinerary: Itinerary
    var destination: String?
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
        focusedJourneyLegs = []
        if !homePath.isEmpty {
            homePath.removeLast()
        }
        homeDetent = .half
    }

    /// Shows one journey option step by step, which the rider tapped: draws it on the map and pushes its plan onto
    /// ``AppRouter/homePath`` (``JourneyDetailView``), raising the sheet to half height where it's lower.
    func showJourneyDetail(_ itinerary: Itinerary, to destination: String? = nil) {
        selectedJourney = itinerary
        focusedJourneyLegs = []
        homePath.append(JourneyDetailRoute(itinerary: itinerary, destination: destination))
        if homeDetent == .peek {
            homeDetent = .half
        }
    }

    /// Leaves the journey's plan for the options, drawing the whole journey again.
    func closeJourneyDetail() {
        focusedJourneyLegs = []
        if !homePath.isEmpty {
            homePath.removeLast()
        }
    }

    /// Zooms the map to some of the selected journey's legs, by their place in its itinerary, such as a ride tapped in
    /// its plan; none zooms back out to the whole journey.
    func showJourneyLegs(_ legs: [Int]) {
        if legs != focusedJourneyLegs {
            focusedJourneyLegs = legs
        }
    }
}
