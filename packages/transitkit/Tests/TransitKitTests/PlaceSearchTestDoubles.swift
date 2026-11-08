import Foundation
import Synchronization
import TransitKit

/// Returns canned suggestions for queries starting with "Gr", nothing otherwise, and records every request.
actor FakePlaceSearchService: PlaceSearchService {
    static let grand = [
        PlaceSuggestion(placeID: "gct", title: "Grand Central Terminal", subtitle: "89 E 42nd St, New York, NY"),
        PlaceSuggestion(placeID: "gap", title: "Grand Army Plaza", subtitle: "Brooklyn, NY"),
    ]

    private(set) var queries: [String] = []
    private(set) var areas: [ServiceArea] = []
    private(set) var sessions: [PlaceSearchSession] = []
    private(set) var detailSessions: [PlaceSearchSession] = []
    private var error: PlaceSearchError?
    private let otherError: (any Error)?

    init(error: PlaceSearchError? = nil, otherError: (any Error)? = nil) {
        self.error = error
        self.otherError = otherError
    }

    func setError(_ error: PlaceSearchError?) {
        self.error = error
    }

    func suggestions(for query: String, in area: ServiceArea, session: PlaceSearchSession) async throws
        -> [PlaceSuggestion]
    {
        queries.append(query)
        areas.append(area)
        sessions.append(session)
        if let error {
            throw error
        }
        if let otherError {
            throw otherError
        }
        return query.hasPrefix("Gr") ? Self.grand : []
    }

    func details(for suggestion: PlaceSuggestion, session: PlaceSearchSession) async throws -> PlaceDetails {
        detailSessions.append(session)
        if let error {
            throw error
        }
        return PlaceDetails(
            placeID: suggestion.placeID,
            name: suggestion.title,
            address: suggestion.subtitle,
            coordinate: Coordinate(latitude: 40.7527, longitude: -73.9772)
        )
    }
}

/// A clock that only moves when the test advances it, so debouncing is tested without waiting.
final class TestClock: Clock, Sendable {
    struct Instant: InstantProtocol {
        var offset: Duration

        func advanced(by duration: Duration) -> Instant {
            Instant(offset: offset + duration)
        }

        func duration(to other: Instant) -> Duration {
            other.offset - offset
        }

        static func < (lhs: Instant, rhs: Instant) -> Bool {
            lhs.offset < rhs.offset
        }
    }

    private struct Sleeper {
        var deadline: Instant
        var continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var now = Instant(offset: .zero)
        var sleepers: [UUID: Sleeper] = [:]
    }

    private let state = Mutex(State())

    var now: Instant {
        state.withLock { $0.now }
    }

    var minimumResolution: Duration {
        .zero
    }

    func sleep(until deadline: Instant, tolerance _: Duration?) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let resume: Result<Void, any Error>? = state.withLock { state in
                    if Task.isCancelled {
                        return .failure(CancellationError())
                    }
                    if deadline <= state.now {
                        return .success(())
                    }
                    state.sleepers[id] = Sleeper(deadline: deadline, continuation: continuation)
                    return nil
                }
                if let resume {
                    continuation.resume(with: resume)
                }
            }
        } onCancel: {
            let sleeper = state.withLock { $0.sleepers.removeValue(forKey: id) }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Moves time on by `duration`, waking every sleeper whose deadline has come.
    func advance(by duration: Duration) {
        let due = state.withLock { state in
            state.now = state.now.advanced(by: duration)
            let due = state.sleepers.filter { $0.value.deadline <= state.now }
            for id in due.keys {
                state.sleepers.removeValue(forKey: id)
            }
            return due.values.map(\.continuation)
        }
        for continuation in due {
            continuation.resume()
        }
    }
}
