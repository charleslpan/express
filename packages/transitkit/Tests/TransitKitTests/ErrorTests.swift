import Foundation
import HTTPTypes
import Testing
@testable import TransitKit

struct ErrorTests {
    let request = PlanRequest(from: .stop(id: "a"), to: .stop(id: "b"))

    func plan(with transport: FixtureTransport) async -> TransitError? {
        do {
            _ = try await TransitClient(transport: transport).plan(request)
            return nil
        } catch {
            return error
        }
    }

    @Test func offline() async {
        let error = await plan(with: FixtureTransport(error: URLError(.notConnectedToInternet)))
        #expect(error == .offline)
    }

    @Test func rateLimited() async {
        let headers: HTTPFields = [.retryAfter: "30"]
        let error = await plan(with: FixtureTransport(status: .tooManyRequests, headers: headers))
        #expect(error == .rateLimited(retryAfter: 30))
    }

    @Test func badRequestCarriesTheMessage() async {
        let body = Data(#"{"error":"unknown stop"}"#.utf8)
        let error = await plan(with: FixtureTransport(status: .badRequest, body: body))
        #expect(error == .server(statusCode: 400, message: "unknown stop"))
    }

    @Test func serverError() async {
        let error = await plan(with: FixtureTransport(status: .serviceUnavailable))
        #expect(error == .server(statusCode: 503, message: nil))
    }

    @Test func decodingError() async {
        let error = await plan(with: FixtureTransport(body: Data(#"{"itineraries":"nope"}"#.utf8)))
        guard case .decoding = error else {
            Issue.record("expected a decoding error, got \(String(describing: error))")
            return
        }
    }
}
