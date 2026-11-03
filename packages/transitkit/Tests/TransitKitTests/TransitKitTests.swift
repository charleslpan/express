import Testing
@testable import TransitKit

struct TransitKitTests {
    @Test func versionIsSet() {
        #expect(!TransitKit.version.isEmpty)
    }
}
