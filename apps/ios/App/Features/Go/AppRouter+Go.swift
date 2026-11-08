extension AppRouter {
    /// Starts a place search from the home sheet's search field: raises the sheet to full and shows search in it.
    ///
    /// Until place search (S3) lands, the sheet shows a placeholder there; S3 fills it in.
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
