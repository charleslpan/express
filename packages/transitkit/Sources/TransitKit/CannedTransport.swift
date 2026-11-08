import Foundation
import HTTPTypes
import OpenAPIRuntime

public extension TransitClient {
    /// A client that never touches the network: it answers each request with the body canned for its operation,
    /// and 404 for any other. For the app's screenshot harness, which shows screens on recorded data.
    ///
    /// - Parameter cannedResponses: Response bodies by operation id: the spec's `operationId` (`trips`, `stops`,
    ///   `plan`, …) or `metrics` for ``realtimeDataAge()``.
    init(baseURL: URL = TransitKit.defaultBaseURL, cannedResponses: [String: Data]) {
        self.init(baseURL: baseURL, transport: CannedTransport(responses: cannedResponses))
    }
}

/// Answers every request from ``responses`` by its operation id.
struct CannedTransport: ClientTransport {
    let responses: [String: Data]

    func send(
        _: HTTPRequest,
        body _: HTTPBody?,
        baseURL _: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        guard let body = responses[operationID] else {
            return (HTTPResponse(status: .notFound), nil)
        }
        return (HTTPResponse(status: .ok, headerFields: [.contentType: "application/json"]), HTTPBody(body))
    }
}
