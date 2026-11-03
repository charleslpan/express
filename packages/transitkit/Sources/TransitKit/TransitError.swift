import Foundation
import HTTPTypes
import OpenAPIRuntime
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Everything a ``TransitClient`` call can fail with, small enough for a screen to switch over.
public enum TransitError: Error, Sendable, Equatable {
    /// The device couldn't reach the server: no connection, a lost connection, or a timeout.
    case offline
    /// The server asked us to slow down (HTTP 429), optionally saying after how many seconds to retry.
    case rateLimited(retryAfter: TimeInterval?)
    /// The server found no way between the two places at that time.
    case noRoute
    /// The server answered with an error status, and the message it gave, if any.
    case server(statusCode: Int, message: String?)
    /// The server's answer didn't match MOTIS's API.
    case decoding(String)
}

extension TransitError {
    /// Maps an error thrown by the generated client, or by its transport, to a ``TransitError``.
    init(_ error: any Error) {
        if let error = error as? TransitError {
            self = error
            return
        }
        let underlying = (error as? ClientError)?.underlyingError ?? error
        if let urlError = underlying as? URLError {
            self = Self.offlineCodes.contains(urlError.code)
                ? .offline
                : .server(statusCode: 0, message: urlError.localizedDescription)
        } else if underlying is DecodingError {
            self = .decoding(String(describing: underlying))
        } else {
            self = .server(statusCode: 0, message: String(describing: underlying))
        }
    }

    /// Maps a response the spec doesn't document (such as 429 or 503) to a ``TransitError``.
    init(undocumentedStatus statusCode: Int, payload: UndocumentedPayload) {
        if statusCode == 429 {
            let retryAfter = payload.headerFields[.retryAfter].flatMap(TimeInterval.init)
            self = .rateLimited(retryAfter: retryAfter)
        } else {
            self = .server(statusCode: statusCode, message: nil)
        }
    }

    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet,
        .networkConnectionLost,
        .timedOut,
        .cannotFindHost,
        .cannotConnectToHost,
        .dnsLookupFailed,
        .dataNotAllowed,
        .internationalRoamingOff,
    ]
}
