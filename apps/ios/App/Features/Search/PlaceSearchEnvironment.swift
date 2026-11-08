import GooglePlacesSwift
import SwiftUI
import TransitKit

extension EnvironmentValues {
    /// The app's place search: Google Places, fixtures for the screenshot harness, or nil where the build has no
    /// Google Maps key, which search shows as unavailable. `ExpressApp` sets it from
    /// ``PlaceSearchServices/make(fixtures:)``.
    @Entry var placeSearchService: (any PlaceSearchService)?

    /// A query place search starts with instead of an empty, focused field: the screenshot harness's, so each search
    /// screen opens in its state without typing.
    @Entry var placeSearchSeed: String?
}

@MainActor
enum PlaceSearchServices {
    /// The service for a launch on `fixtures`, or on live data where they're nil.
    static func make(fixtures: FixtureSet?) -> (any PlaceSearchService)? {
        if let fixtures {
            return fixtures == .noKey ? nil : FixturePlaceSearchService(fixtures: fixtures)
        }
        guard GoogleMapsServices.isPlacesConfigured else { return nil }
        return GooglePlaceSearchService(client: PlacesClient.shared)
    }
}
