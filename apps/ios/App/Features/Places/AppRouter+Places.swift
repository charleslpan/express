import TransitKit

/// Place search's place in the home sheet's navigation stack while you choose a place as Home or Work.
struct ChoosePlaceRoute: Hashable {
    var slot: PlaceSlot
}

extension AppRouter {
    /// One tap from Home or Work: pins `place` on the map and shows ways to get there from the current location,
    /// leaving now, over its card at half height.
    func showJourneys(toSavedPlace place: PlaceDetails) {
        popToRoot()
        showPlace(place)
        showJourneys(to: place)
    }

    /// Opens place search at full height to choose the place for Home or Work (``ChoosePlaceView``).
    func choosePlace(for slot: PlaceSlot) {
        isSearchingPlaces = false
        homePath.append(ChoosePlaceRoute(slot: slot))
        homeDetent = .full
    }

    /// Leaves choosing Home or Work for the home sheet's sections, at half height.
    func endChoosingPlace() {
        if !homePath.isEmpty {
            homePath.removeLast()
        }
        homeDetent = .half
    }
}
