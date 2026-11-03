import Foundation
import Testing
@testable import TransitKit

struct TransitKitTests {
    @Test func versionIsSet() {
        #expect(!TransitKit.version.isEmpty)
    }

    @Test func defaultsToTransitous() {
        #expect(TransitClient().baseURL.absoluteString == "https://api.transitous.org")
    }
}
