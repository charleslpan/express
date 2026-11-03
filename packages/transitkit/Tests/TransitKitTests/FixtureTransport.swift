import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing
@testable import TransitKit

/// A `ClientTransport` that answers every request with a recorded fixture and keeps the requests it saw.
final class FixtureTransport: ClientTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [HTTPRequest] = []
    private let status: HTTPResponse.Status
    private let headers: HTTPFields
    private let body: Data
    private let error: (any Error)?

    /// Answers with a fixture from `Fixtures/<name>.json`.
    convenience init(fixture name: String) throws {
        try self.init(body: Self.fixture(name))
    }

    init(status: HTTPResponse.Status = .ok, headers: HTTPFields = [:], body: Data = Data(), error: (any Error)? = nil) {
        self.status = status
        self.headers = headers
        self.body = body
        self.error = error
    }

    var requests: [HTTPRequest] {
        lock.withLock { recorded }
    }

    func send(
        _ request: HTTPRequest,
        body _: HTTPBody?,
        baseURL _: URL,
        operationID _: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        lock.withLock { recorded.append(request) }
        if let error {
            throw error
        }
        var fields = headers
        fields[.contentType] = "application/json"
        return (HTTPResponse(status: status, headerFields: fields), HTTPBody(body))
    }

    static func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    /// Decodes a fixture's first itinerary straight from JSON, the way the generated client does.
    static func firstItinerary(_ name: String) throws -> Itinerary {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try #require(decoder.decode(PlanResponse.self, from: fixture(name)).itineraries.first)
    }
}

extension HTTPRequest {
    /// The request's query items, decoded.
    var queryItems: [String: String] {
        let components = path.flatMap { URLComponents(string: $0) }
        return Dictionary(
            (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") },
            uniquingKeysWith: { first, _ in first }
        )
    }
}
