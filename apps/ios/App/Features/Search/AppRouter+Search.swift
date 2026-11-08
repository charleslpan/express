import TransitKit

extension AppRouter {
    /// Shows a place picked from search: ends the search, pins the place on the map, and shows its card in the home
    /// sheet at half height.
    func showPlace(_ place: PlaceDetails) {
        isSearchingPlaces = false
        selectedPlace = place
        homeDetent = .half
    }

    /// Closes the place card and takes its pin off the map, returning the sheet to its sections.
    func closePlace() {
        selectedPlace = nil
        homeDetent = .half
    }
}
