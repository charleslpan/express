import Foundation
import HTTPTypes
import OpenAPIRuntime
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// A transport that answers every request from a closure and never touches the network, for the app's screenshot
/// harness and previews: pass it as a ``TransitClient``'s `transport:`.
///
/// ```swift
/// let client = TransitClient(transport: StubTransport { request in
///     switch request.path {
///     case "/api/v6/stoptimes": try fixture("stoptimes-\(request.query["stopId"] ?? "")")
///     default: throw URLError(.fileDoesNotExist)
///     }
/// })
/// ```
///
/// The closure answers with the response body, served as `200 OK` JSON (or Prometheus text for `/metrics`). Throw a
/// `URLError` to fail the request as the network would, such as `URLError(.notConnectedToInternet)` for
/// ``TransitError/offline``.
public struct StubTransport: ClientTransport {
    /// What the closure sees of a request.
    public struct Request: Sendable, Hashable {
        /// The path without its query, such as `/api/v6/stoptimes`.
        public var path: String
        /// The query items by name, such as `["stopId": "us-ny-MTA-NYCSubway_635"]`.
        public var query: [String: String]
    }

    private let respond: @Sendable (Request) async throws -> Data

    public init(_ respond: @escaping @Sendable (Request) async throws -> Data) {
        self.respond = respond
    }

    public func send(
        _ request: HTTPRequest,
        body _: HTTPBody?,
        baseURL _: URL,
        operationID _: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let components = request.path.flatMap { URLComponents(string: $0) }
        let query = Dictionary(
            (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") },
            uniquingKeysWith: { first, _ in first }
        )
        let body = try await respond(Request(path: components?.path ?? "", query: query))
        var fields = HTTPFields()
        fields[.contentType] = components?.path == "/metrics" ? "text/plain" : "application/json"
        return (HTTPResponse(status: .ok, headerFields: fields), HTTPBody(body))
    }
}
