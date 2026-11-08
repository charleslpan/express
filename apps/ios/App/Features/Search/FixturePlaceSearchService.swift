import Foundation
import TransitKit

/// Place search on fixture data, for the screenshot harness: a few real New York places that match the query by
/// name or address, returned at once. `slow-network` never answers, and `offline` fails every request as offline.
struct FixturePlaceSearchService: PlaceSearchService {
    let fixtures: FixtureSet

    func suggestions(for query: String, in _: ServiceArea, session _: PlaceSearchSession) async throws
        -> [PlaceSuggestion]
    {
        try await respond()
        return Self.places
            .filter { $0.matches(query) }
            .map { PlaceSuggestion(placeID: $0.placeID, title: $0.name, subtitle: $0.address) }
    }

    func details(for suggestion: PlaceSuggestion, session _: PlaceSearchSession) async throws -> PlaceDetails {
        try await respond()
        guard let place = Self.places.first(where: { $0.placeID == suggestion.placeID }) else {
            throw PlaceSearchError.failed
        }
        return place
    }

    /// Waits or fails as the fixture set's network does.
    private func respond() async throws {
        switch fixtures {
        case .nycEvening, .nycEveningStale:
            return
        case .slowNetwork:
            try await Task.sleep(for: .seconds(3600))
        case .offline:
            throw PlaceSearchError.offline
        case .noKey:
            throw PlaceSearchError.unavailable
        }
    }

    /// Places as Google describes them, with made-up IDs.
    static let places = [
        PlaceDetails(
            placeID: "fixture-grand-central-terminal",
            name: "Grand Central Terminal",
            address: "89 E 42nd St, New York, NY 10017, USA",
            coordinate: Coordinate(latitude: 40.7527, longitude: -73.9772)
        ),
        PlaceDetails(
            placeID: "fixture-grand-central-42-st",
            name: "Grand Central–42 St",
            address: "New York, NY, USA",
            coordinate: Coordinate(latitude: 40.7519, longitude: -73.9770)
        ),
        PlaceDetails(
            placeID: "fixture-grand-army-plaza",
            name: "Grand Army Plaza",
            address: "Brooklyn, NY 11238, USA",
            coordinate: Coordinate(latitude: 40.6743, longitude: -73.9701)
        ),
        PlaceDetails(
            placeID: "fixture-grand-st",
            name: "Grand St",
            address: "New York, NY 10002, USA",
            coordinate: Coordinate(latitude: 40.7185, longitude: -73.9937)
        ),
        PlaceDetails(
            placeID: "fixture-grand-concourse",
            name: "Grand Concourse",
            address: "Bronx, NY, USA",
            coordinate: Coordinate(latitude: 40.8270, longitude: -73.9228)
        ),
    ]
}

private extension PlaceDetails {
    func matches(_ query: String) -> Bool {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let query = query.trimmingCharacters(in: .whitespaces)
        return name.range(of: query, options: options) != nil || address?.range(of: query, options: options) != nil
    }
}
