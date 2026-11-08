import Foundation
import HTTPTypes
import OpenAPIRuntime

/// Retries a request the server answered with 503 Service Unavailable, a few times a short while apart.
///
/// Express's server answers 503 for the few seconds after a cold start until its first realtime update is in.
/// Only requests without a body are retried (every MOTIS endpoint is a `GET`), since a streamed body can't be
/// sent twice. The last answer, 503 or not, goes back to the caller.
struct RetryMiddleware: ClientMiddleware {
    /// How many times to retry after the first 503.
    var maxRetries = 3
    /// How long to wait before each retry.
    var delay: Duration = .milliseconds(500)
    /// Waits between attempts; tests pass one that returns at once.
    var sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }

    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID _: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var attempt = 0
        while true {
            let (response, responseBody) = try await next(request, body, baseURL)
            guard response.status == .serviceUnavailable, body == nil, attempt < maxRetries else {
                return (response, responseBody)
            }
            attempt += 1
            try await sleep(delay)
        }
    }
}
