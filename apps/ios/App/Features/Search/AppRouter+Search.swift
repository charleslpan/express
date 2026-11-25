import SwiftUI
import TransitKit

extension AppRouter {
    /// Shows a place picked from search: ends the search, pins the place on the map, and shows its card in the home
    /// sheet at half height.
    func showPlace(_ place: PlaceDetails) {
        isSearchingPlaces = false
        selectedPlace = place
        homeDetent = .half
    }

    /// Whether the place card alone fills the home sheet: a place is picked, with no search or journeys over it. The
    /// sheet then has one detent, the card's own height (``placeCardHeight``), so nothing is cut off by a drag.
    var isShowingPlaceCard: Bool {
        selectedPlace != nil && !isSearchingPlaces && homePath.isEmpty
    }

    /// Closes the place card and takes its pin off the map, returning the sheet to its sections.
    func closePlace() {
        selectedPlace = nil
        homeDetent = .half
    }
}
