import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing
@testable import TransitKit

/// A `ClientTransport` that answers 503 a set number of times, then with a fixture.
final class ColdStartTransport: ClientTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var remaining: Int
    private var count = 0
    private let body: Data

    init(unavailable: Int, fixture name: String) throws {
        remaining = unavailable
        body = try FixtureTransport.fixture(name)
    }

    var requests: Int {
        lock.withLock { count }
    }

    func send(
        _: HTTPRequest,
        body _: HTTPBody?,
        baseURL _: URL,
        operationID _: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let unavailable = lock.withLock {
            count += 1
            remaining -= 1
            return remaining >= 0
        }
        if unavailable {
            return (HTTPResponse(status: .serviceUnavailable), nil)
        }
        return (HTTPResponse(status: .ok, headerFields: [.contentType: "application/json"]), HTTPBody(body))
    }
}

/// Records each wait instead of sleeping.
final class Waits: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Duration] = []

    var all: [Duration] {
        lock.withLock { recorded }
    }

    func sleep(_ duration: Duration) {
        lock.withLock { recorded.append(duration) }
    }
}

struct RetryTests {
    let request = PlanRequest(from: .stop(id: "a"), to: .stop(id: "b"))
    let waits = Waits()

    func client(_ transport: any ClientTransport) -> TransitClient {
        let waits = waits
        let retry = RetryMiddleware(sleep: { waits.sleep($0) })
        return TransitClient(baseURL: TransitKit.defaultBaseURL, appVersion: "1.0", transport: transport, retry: retry)
    }

    @Test func retriesA503UntilTheServerAnswers() async throws {
        let transport = try ColdStartTransport(unavailable: 2, fixture: "plan-union-square-to-williamsburg")
        let response = try await client(transport).plan(request)
        #expect(!response.itineraries.isEmpty)
        #expect(transport.requests == 3)
        #expect(waits.all == [.milliseconds(500), .milliseconds(500)])
    }

    @Test func givesUpAfterThreeRetries() async throws {
        let transport = try ColdStartTransport(unavailable: 10, fixture: "plan-union-square-to-williamsburg")
        await #expect(throws: TransitError.server(statusCode: 503, message: nil)) {
            try await client(transport).plan(request)
        }
        #expect(transport.requests == 4)
        #expect(waits.all.count == 3)
    }

    @Test func retriesEveryEndpoint() async throws {
        let transport = try ColdStartTransport(unavailable: 1, fixture: "stoptimes-union-square")
        let response = try await client(transport).departures(DeparturesRequest(stopId: "us-ny-MTA-NYCSubway_635"))
        #expect(!response.stopTimes.isEmpty)
        #expect(transport.requests == 2)
    }

    @Test func doesNotRetryOtherErrors() async throws {
        let transport = FixtureTransport(status: .badGateway)
        await #expect(throws: TransitError.server(statusCode: 502, message: nil)) {
            try await client(transport).plan(request)
        }
        #expect(transport.requests.count == 1)
        #expect(waits.all.isEmpty)
    }
}
