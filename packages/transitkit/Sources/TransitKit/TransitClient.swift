import Foundation
import OpenAPIRuntime
import OpenAPIURLSession
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Plans trips against a MOTIS 2 server (Express's own by default) through the client generated from MOTIS's spec.
///
/// ```swift
/// let client = TransitClient()
/// let response = try await client.plan(PlanRequest(from: .stop(id: "us-ny-MTA-NYCSubway_635"), to: home))
/// ```
public struct TransitClient: Sendable {
    /// The server this client talks to.
    public let baseURL: URL
    let client: Client

    /// - Parameters:
    ///   - baseURL: The MOTIS server's root, without `/api`; defaults to ``TransitKit/defaultBaseURL``.
    ///   - appVersion: Express's version, sent as `User-Agent: Express/<appVersion> (<contact URL>)`.
    ///   - transport: How requests travel; tests pass a fixture transport, so they never touch the network.
    public init(
        baseURL: URL = TransitKit.defaultBaseURL,
        appVersion: String = TransitKit.version,
        transport: any ClientTransport = URLSessionTransport()
    ) {
        self.baseURL = baseURL
        client = Client(
            serverURL: baseURL,
            transport: transport,
            middlewares: [UserAgentMiddleware(appVersion: appVersion)]
        )
    }

    /// Wakes the server with one cheap request (`GET /api/v1/health`), so the first real search lands warm.
    ///
    /// Call it when the app comes to the foreground: the server scales to zero about a minute after its last
    /// request and takes over a second to start. Never call it on a timer. It never throws; any answer,
    /// even an error, has done its job.
    public func warmUp() async {
        _ = try? await client.health()
    }

    /// Plans itineraries for a trip (`GET /api/v6/plan`).
    ///
    /// - Throws: ``TransitError/noRoute`` when the first page holds no itinerary at all.
    public func plan(_ request: PlanRequest) async throws(TransitError) -> PlanResponse {
        let response: PlanResponse
        do {
            switch try await client.plan(query: request.query) {
            case let .ok(success):
                response = try success.body.json
            case let .badRequest(error):
                throw TransitError.server(statusCode: 400, message: try? error.body.json.error)
            case let .notFound(error):
                throw TransitError.server(statusCode: 404, message: try? error.body.json.error)
            case let .unprocessableContent(error):
                throw TransitError.server(statusCode: 422, message: try? error.body.json.error)
            case let .internalServerError(error):
                throw TransitError.server(statusCode: 500, message: try? error.body.json.error)
            case let .undocumented(statusCode, payload):
                throw TransitError(undocumentedStatus: statusCode, payload: payload)
            }
        } catch {
            throw TransitError(error)
        }
        if request.pageCursor == nil, response.itineraries.isEmpty, response.direct.isEmpty {
            throw .noRoute
        }
        return response
    }

    /// Re-fetches an itinerary with the latest schedule and realtime data (`GET /api/v6/refresh-itinerary`).
    ///
    /// MOTIS marks the endpoint experimental and rebuilds only walk-to-station itineraries; where it can't,
    /// plan again from the same request.
    public func refresh(_ itinerary: Itinerary) async throws(TransitError) -> Itinerary {
        do {
            switch try await client.refreshItinerary(query: .init(itineraryId: itinerary.id)) {
            case let .ok(success):
                return try success.body.json
            case let .badRequest(error):
                throw TransitError.server(statusCode: 400, message: try? error.body.json.error)
            case let .internalServerError(error):
                throw TransitError.server(statusCode: 500, message: try? error.body.json.error)
            case let .undocumented(statusCode, payload):
                throw TransitError(undocumentedStatus: statusCode, payload: payload)
            }
        } catch {
            throw TransitError(error)
        }
    }
}
