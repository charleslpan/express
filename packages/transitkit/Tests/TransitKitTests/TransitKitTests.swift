import Foundation
import Testing
@testable import TransitKit

struct TransitKitTests {
    @Test func versionIsSet() {
        #expect(!TransitKit.version.isEmpty)
    }

    @Test func defaultsToExpressServer() {
        #expect(TransitClient().baseURL == TransitServer.express.baseURL)
        #expect(TransitClient().baseURL.absoluteString == "https://express-server-cyan-zeta.vercel.app")
    }

    @Test func transitousStaysSelectable() {
        #expect(TransitServer(rawValue: "transitous")?.baseURL.absoluteString == "https://api.transitous.org")
        #expect(TransitClient(baseURL: TransitServer.transitous.baseURL).baseURL.host == "api.transitous.org")
    }
}
