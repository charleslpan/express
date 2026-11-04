import SwiftUI
import Testing
@testable import GlassUI

struct ControlTests {
    @Test func controlsMeetTheMinimumTapTarget() {
        #expect(GlassMetrics.minimumTarget >= 44)
        #expect(GlassMetrics.floatingControl >= GlassMetrics.minimumTarget)
    }

    @MainActor @Test func overridesDefaultToTheSystemSettings() {
        let environment = EnvironmentValues()
        #expect(!environment.forcesOpaqueGlass)
        #expect(!environment.forcesHighContrastGlass)
    }
}
