import CoreLocation
import Foundation
import GooglePlacesSwift
import TransitKit

/// Place search on Google Places (New), through the Places Swift SDK: autocomplete restricted to the service area,
/// then the picked place's name, address, and coordinate.
///
/// Each ``PlaceSearchSession`` maps to one `AutocompleteSessionToken`, passed with every autocomplete request and the
/// details fetch that ends it, so Google bills the search and its pick as one session. Express keeps nothing it
/// fetches here beyond the place ID.
actor GooglePlaceSearchService: PlaceSearchService {
    private let client: PlacesClient
    /// The token for the session in progress; a new session gets a new token.
    private var current: (session: PlaceSearchSession, token: AutocompleteSessionToken)?

    init(client: PlacesClient) {
        self.client = client
    }

    func suggestions(for query: String, in area: ServiceArea, session: PlaceSearchSession) async throws
        -> [PlaceSuggestion]
    {
        let request = AutocompleteRequest(
            query: query,
            sessionToken: token(for: session),
            filter: AutocompleteFilter(coordinateRegionRestriction: area.region)
        )
        switch await client.fetchAutocompleteSuggestions(with: request) {
        case let .success(suggestions):
            return suggestions.compactMap { PlaceSuggestion($0) }
        case let .failure(error):
            throw PlaceSearchError(error)
        }
    }

    func details(for suggestion: PlaceSuggestion, session: PlaceSearchSession) async throws -> PlaceDetails {
        let request = FetchPlaceRequest(
            placeID: suggestion.placeID,
            placeProperties: [.placeID, .displayName, .formattedAddress, .coordinate],
            sessionToken: token(for: session)
        )
        switch await client.fetchPlace(with: request) {
        case let .success(place):
            // The fetch ends the session; the next search starts a new one.
            current = nil
            guard let details = PlaceDetails(
                placeID: place.placeID ?? suggestion.placeID,
                name: place.displayName,
                address: place.formattedAddress,
                latitude: place.location.latitude,
                longitude: place.location.longitude,
                suggestion: suggestion
            ) else { throw PlaceSearchError.failed }
            return details
        case let .failure(error):
            throw PlaceSearchError(error)
        }
    }

    private func token(for session: PlaceSearchSession) -> AutocompleteSessionToken {
        if let current, current.session == session {
            return current.token
        }
        let token = AutocompleteSessionToken()
        current = (session, token)
        return token
    }
}

extension PlaceSuggestion {
    /// The suggestion for one of Google's, or nil where it isn't a place or has nothing to show.
    init?(_ suggestion: AutocompleteSuggestion) {
        guard case let .place(place) = suggestion else { return nil }
        self.init(
            placeID: place.placeID,
            primaryText: String(place.attributedPrimaryText.characters),
            secondaryText: place.attributedSecondaryText.map { String($0.characters) }
        )
    }
}

extension PlaceSearchError {
    /// How a Places SDK error shows: offline, unavailable where the key is missing or refused, or failed.
    init(_ error: PlacesError) {
        switch error {
        case .network:
            self = .offline
        case .keyInvalid, .keyExpired, .accessNotConfigured, .incorrectBundleIdentifier:
            self = .unavailable
        default:
            self = .failed
        }
    }
}

private extension ServiceArea {
    /// The area as the rectangle Google restricts autocomplete to.
    var region: RectangularCoordinateRegion? {
        RectangularCoordinateRegion(
            northEast: CLLocationCoordinate2D(latitude: north, longitude: east),
            southWest: CLLocationCoordinate2D(latitude: south, longitude: west)
        )
    }
}
