import Foundation
import Observation

/// A place a search suggests as the user types, such as "Grand Central Terminal, 89 E 42nd St".
///
/// It holds only what the suggestion list shows and the provider's place ID, which ``PlaceSearchService`` fetches the
/// details of once the user picks it.
public struct PlaceSuggestion: Sendable, Hashable, Identifiable {
    /// The provider's ID for the place (a Google place ID), the one thing Express may keep.
    public var placeID: String
    /// The place's name, or the first line of its address.
    public var title: String
    /// Where it is, such as its street address or neighbourhood; nil where the provider gives none.
    public var subtitle: String?

    public var id: String {
        placeID
    }

    public init(placeID: String, title: String, subtitle: String? = nil) {
        self.placeID = placeID
        self.title = title
        self.subtitle = subtitle
    }

    /// A suggestion from a provider's raw text, trimmed; nil where it has no place ID or no title to show.
    public init?(placeID: String, primaryText: String, secondaryText: String?) {
        let title = primaryText.trimmed
        guard !placeID.isEmpty, let title else { return nil }
        self.init(placeID: placeID, title: title, subtitle: secondaryText?.trimmed)
    }
}

/// A place the user picked, with what the map and the place card show: fetched live each time, never stored. Only
/// ``placeID`` may be persisted (Google's terms).
public struct PlaceDetails: Sendable, Hashable, Identifiable {
    public var placeID: String
    public var name: String
    /// Its formatted address; nil where the provider gives none or it would only repeat the name.
    public var address: String?
    public var coordinate: Coordinate

    public var id: String {
        placeID
    }

    public init(placeID: String, name: String, address: String? = nil, coordinate: Coordinate) {
        self.placeID = placeID
        self.name = name
        self.address = address
        self.coordinate = coordinate
    }

    /// Details from a provider's raw fields, falling back to the picked suggestion's text where a field is missing.
    /// Nil where there's no name to show or the coordinate isn't a real point on Earth (such as CoreLocation's
    /// invalid coordinate, which a place fetched without its location carries).
    public init?(
        placeID: String,
        name: String?,
        address: String?,
        latitude: Double,
        longitude: Double,
        suggestion: PlaceSuggestion? = nil
    ) {
        guard (-90 ... 90).contains(latitude), (-180 ... 180).contains(longitude),
              let name = name?.trimmed ?? suggestion?.title
        else { return nil }
        let address = address?.trimmed ?? suggestion?.subtitle
        self.init(
            placeID: placeID.isEmpty ? suggestion?.placeID ?? "" : placeID,
            name: name,
            address: address == name ? nil : address,
            coordinate: Coordinate(latitude: latitude, longitude: longitude)
        )
        guard !self.placeID.isEmpty else { return nil }
    }
}

/// One autocomplete session: every keystroke of a search and the details fetch for the place picked from it share
/// one, so the provider bills them together (Google's session tokens). ``PlaceSearch`` starts one at the first
/// keystroke and ends it once a pick's details arrive or the search is abandoned.
public struct PlaceSearchSession: Sendable, Hashable {
    public let id: UUID

    public init(id: UUID = UUID()) {
        self.id = id
    }
}

/// Why a search or a pick failed, in the terms the search screen shows.
public enum PlaceSearchError: Error, Sendable, Hashable {
    /// The device couldn't reach the provider.
    case offline
    /// The build has no working key for the provider, so search can't work at all.
    case unavailable
    /// Anything else, such as a server error; worth retrying.
    case failed
}

/// Finds places by name or address, and fetches the details of the one picked: Google Places in the app, fixtures
/// in the screenshot harness and tests. Implementations throw ``PlaceSearchError``.
public protocol PlaceSearchService: Sendable {
    /// Suggestions for `query` within `area`, in the provider's order, billed to `session`.
    func suggestions(for query: String, in area: ServiceArea, session: PlaceSearchSession) async throws
        -> [PlaceSuggestion]
    /// The details of the picked `suggestion`, which ends `session` for billing.
    func details(for suggestion: PlaceSuggestion, session: PlaceSearchSession) async throws -> PlaceDetails
}

/// Place search as the user types: debounces the query, asks the ``PlaceSearchService`` for suggestions within the
/// service area, and fetches the details of the one picked, all within one ``PlaceSearchSession``.
///
/// Set ``query`` through ``update(query:)`` on every keystroke and show ``status``. Without a service (a build with
/// no API key) the status stays ``Status/unavailable``.
@MainActor
@Observable
public final class PlaceSearch {
    /// What the search screen shows.
    public enum Status: Sendable, Hashable {
        /// Search can't work in this build (no API key).
        case unavailable
        /// The query is empty: show a hint.
        case idle
        /// Waiting for the first suggestions of this query.
        case loading
        /// The suggestions for ``PlaceSearch/query``, never empty.
        case results([PlaceSuggestion])
        /// The provider found nothing for ``PlaceSearch/query``.
        case noResults
        /// The last request failed; ``PlaceSearch/retry()`` tries it again.
        case failed(PlaceSearchError)
    }

    /// What the user typed.
    public private(set) var query = ""
    public private(set) var status: Status
    /// The suggestion whose details are being fetched, while they are.
    public private(set) var picking: PlaceSuggestion?
    /// Why the last pick failed, until the next pick or keystroke.
    public private(set) var pickError: PlaceSearchError?
    /// The session the current search bills to: started at the first keystroke, ended by a successful pick or
    /// ``reset()``.
    public private(set) var session: PlaceSearchSession?

    /// The debounced request for the current query; tests await it.
    private(set) var searchTask: Task<Void, Never>?

    private let service: (any PlaceSearchService)?
    private let area: ServiceArea
    /// Makes the debounce wait for a keystroke, measured from when it's called.
    private let debounceDelay: @MainActor () -> @Sendable () async throws -> Void

    /// A search through `service` (nil where the build has no key) within `area`, asking only once the query has
    /// been still for `debounce` on `clock`.
    public init<C: Clock>(
        service: (any PlaceSearchService)?,
        area: ServiceArea = .nyc,
        debounce: Duration = .milliseconds(300),
        clock: C = ContinuousClock()
    ) where C.Duration == Duration {
        self.service = service
        self.area = area
        status = service == nil ? .unavailable : .idle
        debounceDelay = {
            let deadline = clock.now.advanced(by: debounce)
            return { try await clock.sleep(until: deadline, tolerance: nil) }
        }
    }

    /// Takes the query as typed: shows the hint for an empty one, and otherwise asks for suggestions once typing
    /// pauses. The first non-empty query starts a session.
    public func update(query newQuery: String) {
        guard newQuery != query else { return }
        query = newQuery
        pickError = nil
        search(after: debounceDelay())
    }

    /// Asks again for the current query's suggestions, at once, after a failure.
    public func retry() {
        search(after: nil)
    }

    /// Fetches the details of `suggestion` in the current session, which ends once they arrive; nil (with
    /// ``pickError`` set) where the fetch fails, keeping the session so a retry still bills with it.
    public func pick(_ suggestion: PlaceSuggestion) async -> PlaceDetails? {
        guard let service, picking == nil else { return nil }
        let session = session ?? PlaceSearchSession()
        self.session = session
        picking = suggestion
        pickError = nil
        defer { picking = nil }
        do {
            let details = try await service.details(for: suggestion, session: session)
            searchTask?.cancel()
            self.session = nil
            return details
        } catch {
            pickError = error as? PlaceSearchError ?? .failed
            return nil
        }
    }

    /// Clears ``pickError`` once it has been shown.
    public func dismissPickError() {
        pickError = nil
    }

    /// Abandons the search: empties the query and ends the session, so the next search starts a new one.
    public func reset() {
        searchTask?.cancel()
        searchTask = nil
        query = ""
        session = nil
        picking = nil
        pickError = nil
        if service != nil {
            status = .idle
        }
    }

    private func search(after delay: (@Sendable () async throws -> Void)?) {
        searchTask?.cancel()
        searchTask = nil
        guard let service else { return }
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            status = .idle
            return
        }
        let session = session ?? PlaceSearchSession()
        self.session = session
        // Keep the last suggestions on screen while the next ones load, so the list doesn't flash as you type.
        if !status.isShowingResults {
            status = .loading
        }
        let area = area
        searchTask = Task { [weak self] in
            do {
                try await delay?()
                let suggestions = try await service.suggestions(for: query, in: area, session: session)
                try Task.checkCancellation()
                self?.status = suggestions.isEmpty ? .noResults : .results(suggestions)
            } catch is CancellationError {
                // A newer keystroke took over.
            } catch {
                guard !Task.isCancelled else { return }
                self?.status = .failed(error as? PlaceSearchError ?? .failed)
            }
        }
    }
}

private extension PlaceSearch.Status {
    var isShowingResults: Bool {
        if case .results = self {
            return true
        }
        return false
    }
}

private extension String {
    /// The string without surrounding whitespace, or nil where nothing is left.
    var trimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
