extension AppRouter {
    /// Starts a place search from the home sheet's search field: raises the sheet to full and shows search in it
    /// (``PlaceSearchPanel``).
    func showPlaceSearch() {
        isSearchingPlaces = true
        homeDetent = .full
    }

    /// Ends a place search and returns the sheet to its sections, at half height.
    func endPlaceSearch() {
        isSearchingPlaces = false
        homeDetent = .half
    }
}
