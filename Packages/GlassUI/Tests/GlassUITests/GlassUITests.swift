import Testing
@testable import GlassUI

struct GlassUITests {
    @Test func versionIsSet() {
        #expect(!GlassUI.version.isEmpty)
    }
}
