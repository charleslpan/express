import Foundation
import HTTPTypes
import OpenAPIRuntime
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// A transport that answers from recorded data instead of the network, by operation, for the app's screenshot
/// harness and previews:
///
/// ```swift
/// let client = TransitClient(transport: CannedTransport { operation in
///     operation == "plan" ? .json(planData) : .offline
/// })
/// ```
///
/// The operation is the generated client's operation ID (`plan`, `stoptimes`, `health`, …), or `metrics` for
/// ``TransitClient/realtimeDataAge()``.
public struct CannedTransport: ClientTransport {
    /// How the transport answers one request.
    public enum Answer: Sendable {
        /// 200 with a JSON body.
        case json(Data)
        /// 200 with a plain-text body, such as `/metrics`.
        case text(String)
        /// An error status with an empty body.
        case status(Int)
        /// No connection: fails as ``TransitError/offline``.
        case offline
        /// Never answers, so the caller stays loading until it's cancelled.
        case never
    }

    private let answer: @Sendable (String) -> Answer

    /// A transport that answers each request with what `answer` returns for its operation ID.
    public init(answer: @escaping @Sendable (_ operationID: String) -> Answer) {
        self.answer = answer
    }

    public func send(
        _: HTTPRequest,
        body _: HTTPBody?,
        baseURL _: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        switch answer(operationID) {
        case let .json(data):
            (HTTPResponse(status: .ok, headerFields: [.contentType: "application/json"]), HTTPBody(data))
        case let .text(text):
            (HTTPResponse(status: .ok, headerFields: [.contentType: "text/plain"]), HTTPBody(text))
        case let .status(code):
            (HTTPResponse(status: .init(code: code)), nil)
        case .offline:
            throw URLError(.notConnectedToInternet)
        case .never:
            try await Task.sleep(for: .seconds(24 * 60 * 60))
            throw CancellationError()
        }
    }
}
