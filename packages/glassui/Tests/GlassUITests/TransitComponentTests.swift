import Testing
@testable import GlassUI

struct LineColorTests {
    @Test func parsesHex() throws {
        let red = try #require(LineColor(hex: "#EE352E"))
        #expect(abs(red.red - 238.0 / 255) < 0.000_1)
        #expect(abs(red.green - 53.0 / 255) < 0.000_1)
        #expect(abs(red.blue - 46.0 / 255) < 0.000_1)
        #expect(LineColor(hex: "ee352e") == red)
        #expect(LineColor(hex: "EE35") == nil)
        #expect(LineColor(hex: "GGGGGG") == nil)
    }

    @Test func contrastMatchesWCAG() {
        #expect(abs(LineColor.black.contrastRatio(with: .white) - 21) < 0.01)
        #expect(LineColor.white.contrastRatio(with: .white) == 1)
    }

    @Test(arguments: [
        ("FCCC0A", LineColor.black), // N, Q, R, W yellow
        ("00AEEF", LineColor.black), // local bus light blue
        ("EE352E", LineColor.white), // 1, 2, 3 red
        ("00933C", LineColor.white), // 4, 5, 6 green
        ("0039A6", LineColor.white), // A, C, E blue
        ("808183", LineColor.white), // shuttle grey
    ])
    func picksLegibleText(hex: String, expected: LineColor) throws {
        let color = try #require(LineColor(hex: hex))
        #expect(color.legibleText == expected)
    }
}

struct TransitLineTests {
    private let green = LineColor(red: 0, green: 0.58, blue: 0.24)

    @Test func badgeStyleFollowsModeAndName() {
        #expect(TransitLine(name: "6", mode: .subway, color: green).badgeStyle == .bullet)
        #expect(TransitLine(name: "6", mode: .subway, color: green, isExpress: true).badgeStyle == .diamond)
        #expect(TransitLine(name: "SIR", mode: .rail, color: green).badgeStyle == .pill)
        #expect(TransitLine(name: "M15", mode: .bus, color: green).badgeStyle == .pill)
    }

    @Test func usesTheFeedsTextColourFirst() {
        let line = TransitLine(name: "N", mode: .subway, color: .white, textColor: .white)
        #expect(line.resolvedTextColor == .white)
        #expect(TransitLine(name: "N", mode: .subway, color: .white).resolvedTextColor == .black)
    }

    @Test(arguments: [
        ("M15 SBS", TravelMode.bus, false, "M15 Select Bus"),
        ("B44", TravelMode.bus, false, "B44 bus"),
        ("X27", TravelMode.bus, false, "X27 Express Bus"),
        ("BxM2", TravelMode.bus, false, "BxM2 Express Bus"),
        ("6", TravelMode.subway, true, "6 express train"),
        ("A", TravelMode.subway, false, "A train"),
        ("SIR", TravelMode.rail, false, "Staten Island Railway"),
    ])
    func speaksNames(name: String, mode: TravelMode, express: Bool, spoken: String) {
        #expect(TransitLine(name: name, mode: mode, color: green, isExpress: express).accessibilityName == spoken)
    }

    @Test func expressAndLocalHaveDistinctIDs() {
        let local = TransitLine(name: "7", mode: .subway, color: green)
        let express = TransitLine(name: "7", mode: .subway, color: green, isExpress: true)
        #expect(local.id != express.id)
    }
}

struct DepartureTimeTests {
    @Test func labels() {
        #expect(DepartureTime(minutes: 0, status: .live).text == "Now")
        #expect(DepartureTime(minutes: 4, status: .live).text == "4 min")
        #expect(DepartureTime(minutes: -2, status: .live).minutes == 0)
        #expect(DepartureTime(minutes: 3, status: .live).accessibilityLabel == "3 minutes, live")
        #expect(DepartureTime(minutes: 7, status: .delayed(minutes: 2)).accessibilityLabel
            == "7 minutes, live, 2 minutes late")
        #expect(DepartureTime(minutes: 8, status: .uncertain).accessibilityLabel == "8 minutes, may not be real time")
    }
}

struct JourneySegmentBarTests {
    @Test func sharesWidthByWeight() {
        let widths = JourneySegmentBar.widths(weights: [1, 3], minimums: [0, 0], available: 400)
        #expect(widths == [100, 300])
    }

    @Test func keepsMinimumsAndSharesTheRest() {
        // The 1-minute walk would get 10 points; it keeps its 30, and the rides share the other 380 as 1:1.
        let widths = JourneySegmentBar.widths(weights: [1, 20, 20], minimums: [30, 40, 40], available: 410)
        #expect(widths[0] == 30)
        #expect(abs(widths[1] - 190) < 0.001)
        #expect(abs(widths[2] - 190) < 0.001)
        #expect(abs(widths.reduce(0, +) - 410) < 0.001)
    }

    @Test func shrinksMinimumsWhenTheyDontFit() {
        let widths = JourneySegmentBar.widths(weights: [1, 1], minimums: [60, 140], available: 100)
        #expect(widths == [30, 70])
    }

    @Test func handlesNoLegs() {
        #expect(JourneySegmentBar.widths(weights: [], minimums: [], available: 100).isEmpty)
    }
}
