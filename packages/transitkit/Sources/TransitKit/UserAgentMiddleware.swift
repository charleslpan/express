import Foundation
import HTTPTypes
import OpenAPIRuntime

/// Sets `User-Agent: Express/<version> (<contact URL>)` on every request, as Transitous's usage policy requires.
struct UserAgentMiddleware: ClientMiddleware {
    /// The header's value, such as `Express/1.0 (https://github.com/charleslpan/express)`.
    let userAgent: String

    init(appVersion: String, contactURL: String = TransitKit.contactURL) {
        userAgent = "Express/\(appVersion) (\(contactURL))"
    }

    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID _: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        request.headerFields[.userAgent] = userAgent
        return try await next(request, body, baseURL)
    }
}
