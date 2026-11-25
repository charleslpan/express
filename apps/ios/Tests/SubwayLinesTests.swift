import Foundation
import Testing
import TransitKit
@testable import Express

struct SubwayLinesTests {
    @Test func decodesTheGeneratorsJSON() throws {
        let json = """
        {"precision":5,"lines":[{"colors":["0062CF","EB6800"],"path":"_p~iF~ps|U_ulLnnqC_mqNvxq`@"}]}
        """
        let lines = try SubwayLines(data: Data(json.utf8))

        #expect(lines.lines.count == 1)
        #expect(lines.lines[0].colors == ["0062CF", "EB6800"])
        #expect(lines.lines[0].coordinates.count == 3)
        #expect(abs(lines.lines[0].coordinates[0].latitude - 38.5) < 1e-6)
        #expect(abs(lines.lines[0].coordinates[0].longitude - -120.2) < 1e-6)
    }

    @Test func bundledLinesCoverTheSubwayInsideNewYork() {
        let lines = SubwayLines.bundled.lines
        let bounds = CoordinateBounds(
            southWest: Coordinate(latitude: 40.45, longitude: -74.30),
            northEast: Coordinate(latitude: 40.95, longitude: -73.65)
        )

        #expect(lines.count > 50)
        for line in lines {
            #expect((1 ... 4).contains(line.colors.count))
            #expect(line.colors.allSatisfy { $0.count == 6 && UInt32($0, radix: 16) != nil })
            #expect(line.coordinates.count >= 2)
            #expect(line.coordinates.allSatisfy(bounds.contains))
        }
        // The MTA's blue (A, C, E), orange (B, D, F, M), and yellow (N, Q, R, W) trunks are all there.
        let colors = Set(lines.flatMap(\.colors))
        #expect(colors.isSuperset(of: ["0062CF", "EB6800", "F6BC26", "D82233", "009952", "9A38A1"]))
    }

    @Test func lineWidthsGrowWithZoomAndHideBelowTheRegion() {
        #expect(SubwayLinesOverlay.widthStep(atZoom: 8.9) == nil)
        #expect(SubwayLinesOverlay.widthStep(atZoom: 9) == 0)
        #expect(SubwayLinesOverlay.widthStep(atZoom: MapCamera.newYork.zoom) == 2)
        #expect(SubwayLinesOverlay.widthStep(atZoom: 16) == 6)
        #expect(SubwayLinesOverlay.widthStep(atZoom: 21) == SubwayLinesOverlay.baseWidths.count - 1)

        let widths = (9 ... 20).compactMap { SubwayLinesOverlay.widthStep(atZoom: Float($0)) }.map {
            SubwayLinesOverlay.baseWidths[$0]
        }
        #expect(widths == widths.sorted())
    }
}
