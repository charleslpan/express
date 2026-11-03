import Testing
@testable import GlassUI

struct TokenTests {
    @Test func spacingStepsGrow() {
        let values = Spacing.steps.map(\.value)
        #expect(values == values.sorted())
        #expect(Set(values).count == values.count)
        #expect(values.allSatisfy { $0.truncatingRemainder(dividingBy: 2) == 0 })
    }

    @Test func radiusStepsGrow() {
        let values = Radius.steps.map(\.value)
        #expect(values == values.sorted())
        #expect(Set(values).count == values.count)
    }

    @Test func concentricRadiusSubtractsTheInset() {
        #expect(Radius.concentric(outer: Radius.xl, inset: Spacing.xs) == 26)
        #expect(Radius.concentric(outer: Radius.sm, inset: Spacing.md) == 0)
    }

    @Test func travelModesAreDistinct() {
        let modes = TravelMode.allCases
        #expect(Set(modes.map(\.symbolName)).count == modes.count)
        #expect(Set(modes.map(\.title)).count == modes.count)
        #expect(TravelMode(rawValue: "cable-car") == .cableCar)
    }

    @Test func typographyRolesAreDistinct() {
        #expect(Set(Typography.allCases.map(\.rawValue)).count == Typography.allCases.count)
    }
}
