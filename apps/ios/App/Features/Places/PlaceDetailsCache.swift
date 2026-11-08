import Foundation
import GooglePlacesSwift
import Observation
import TransitKit

/// Fetches a place's details (name, address, coordinate) by its Google place ID, for places Express remembers only by
/// ID: Google Places in the app, place search's fixtures in the screenshot harness.
protocol PlaceLookupService: Sendable {
    func details(forPlaceID placeID: String) async throws -> PlaceDetails
}

/// The session's details of remembered places, by place ID, in memory only: Google's terms forbid storing names and
/// addresses, so each launch fetches them again as they're shown. ``PlaceStore`` owns it as ``PlaceStore/details``
/// and caches each fetched coordinate for its 30 days.
@MainActor
@Observable
final class PlaceDetailsCache {
    /// Where a place's details stand.
    enum Entry: Equatable {
        case loading
        case loaded(PlaceDetails)
        case failed
    }

    private(set) var entries: [String: Entry] = [:]

    /// Runs on each fetched place, so the store can refresh its cached coordinate.
    @ObservationIgnored var onFetch: (@MainActor (PlaceDetails) -> Void)?
    private let lookup: (any PlaceLookupService)?
    @ObservationIgnored private var inFlight: [String: Task<PlaceDetails?, Never>] = [:]

    init(lookup: (any PlaceLookupService)?) {
        self.lookup = lookup
    }

    /// The place's details, where they've been fetched this session.
    func details(for placeID: String) -> PlaceDetails? {
        if case let .loaded(details) = entries[placeID] {
            return details
        }
        return nil
    }

    /// Keeps details fetched elsewhere, such as a place picked in search, so they needn't be fetched again.
    func remember(_ details: PlaceDetails) {
        entries[details.placeID] = .loaded(details)
    }

    /// Drops the place's details, as a new launch would, so they're fetched again: the screenshot harness's, to show
    /// a row still loading.
    func forget(_ placeID: String) {
        entries[placeID] = nil
    }

    /// The place's details: from this session where they're here, else fetched live (once, however many ask at a
    /// time). Nil where the fetch fails or the build can't look places up; a later call tries again.
    @discardableResult
    func load(_ placeID: String) async -> PlaceDetails? {
        if let details = details(for: placeID) {
            return details
        }
        if let task = inFlight[placeID] {
            return await task.value
        }
        guard let lookup else {
            entries[placeID] = .failed
            return nil
        }
        entries[placeID] = .loading
        let task = Task { try? await lookup.details(forPlaceID: placeID) }
        inFlight[placeID] = task
        let details = await task.value
        inFlight[placeID] = nil
        if let details {
            entries[placeID] = .loaded(details)
            onFetch?(details)
        } else {
            entries[placeID] = .failed
        }
        return details
    }
}

/// Looks places up on Google Places (New) by ID, without an autocomplete session: these are places picked before,
/// not the end of a search. Asks only for the fields the card and the recents list show.
actor GooglePlaceLookupService: PlaceLookupService {
    private let client: PlacesClient

    init(client: PlacesClient) {
        self.client = client
    }

    func details(forPlaceID placeID: String) async throws -> PlaceDetails {
        let request = FetchPlaceRequest(
            placeID: placeID,
            placeProperties: [.placeID, .displayName, .formattedAddress, .coordinate]
        )
        switch await client.fetchPlace(with: request) {
        case let .success(place):
            guard let details = PlaceDetails(
                placeID: place.placeID ?? placeID,
                name: place.displayName,
                address: place.formattedAddress,
                latitude: place.location.latitude,
                longitude: place.location.longitude
            ) else { throw PlaceSearchError.failed }
            return details
        case let .failure(error):
            throw PlaceSearchError(error)
        }
    }
}

/// Looks places up through place search's details fetch, each in a session of its own: the screenshot harness's,
/// over search's fixtures, which bill nothing.
struct SearchPlaceLookupService: PlaceLookupService {
    let search: any PlaceSearchService

    func details(forPlaceID placeID: String) async throws -> PlaceDetails {
        try await search.details(for: PlaceSuggestion(placeID: placeID, title: ""), session: PlaceSearchSession())
    }
}

@MainActor
enum PlaceLookupServices {
    /// The lookup for a launch on `fixtures` (through `search`, their place search), or on Google Places where they're
    /// nil; nil where the build has no Places key.
    static func make(fixtures: FixtureSet?, search: (any PlaceSearchService)?) -> (any PlaceLookupService)? {
        if fixtures != nil {
            return search.map { SearchPlaceLookupService(search: $0) }
        }
        guard GoogleMapsServices.isPlacesConfigured else { return nil }
        return GooglePlaceLookupService(client: PlacesClient.shared)
    }
}
