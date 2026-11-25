import GoogleMaps
import SwiftUI
import UIKit

/// Draws ``SubwayLines`` on a `GMSMapView` for ``MapView``, beneath everything else on the map.
///
/// Each piece of track is a stripe of its routes' colours (concentric, so a shared stretch of the A and the F shows
/// both) over a darker casing, which keeps yellow and orange readable on the light map and every colour apart from
/// the roads on the dark one. Google's polylines have a fixed width in points, so the widths are set again at each
/// zoom step: thin in the city-wide view, wider as streets appear. The lines hide where the map shows a selected
/// route, trip or journey, so that route reads clearly.
@MainActor
final class SubwayLinesOverlay {
    /// A line's casing and stripes, drawn as polylines.
    private struct Drawn {
        var colors: [UIColor]
        var casing: GMSPolyline
        var stripes: [GMSPolyline]
    }

    private let source: SubwayLines
    private var drawn: [Drawn] = []
    private var isVisible = false
    private var colorScheme: ColorScheme?
    private var widthStep: Int?

    init(source: SubwayLines = .bundled) {
        self.source = source
    }

    /// The line widths in points for zoom `zoom`, by step: 0 is the city-wide view, 6 a block.
    static let baseWidths: [CGFloat] = [1.5, 2, 2.5, 3.5, 4.5, 5.5, 6.5]

    /// Below this zoom (the region rather than the city) no lines show.
    static let minimumZoom: Float = 9

    /// The step in ``baseWidths`` for a zoom level, or nil where the lines hide.
    static func widthStep(atZoom zoom: Float) -> Int? {
        guard zoom >= minimumZoom else { return nil }
        let thresholds: [Float] = [10.5, 12, 13, 14, 15, 16]
        return thresholds.firstIndex { zoom < $0 } ?? thresholds.count
    }

    /// Shows or hides the lines, and styles them for the map's zoom and the color scheme.
    func update(visible: Bool, colorScheme: ColorScheme, on mapView: GMSMapView) {
        guard visible else {
            hide()
            return
        }
        guard let step = Self.widthStep(atZoom: mapView.camera.zoom) else {
            hide()
            return
        }
        if drawn.isEmpty {
            drawn = source.lines.map(make)
            self.colorScheme = nil
            widthStep = nil
        }
        if !isVisible {
            isVisible = true
            drawn.forEach { line in
                line.casing.map = mapView
                line.stripes.forEach { $0.map = mapView }
            }
        }
        if self.colorScheme != colorScheme {
            self.colorScheme = colorScheme
            drawn.forEach { applyColors($0, colorScheme: colorScheme) }
        }
        if widthStep != step {
            widthStep = step
            drawn.forEach { applyWidths($0, base: Self.baseWidths[step]) }
        }
    }

    /// Takes the lines off the map, keeping them to put back.
    private func hide() {
        guard isVisible else { return }
        isVisible = false
        drawn.forEach { line in
            line.casing.map = nil
            line.stripes.forEach { $0.map = nil }
        }
    }

    private func make(_ line: SubwayLines.Line) -> Drawn {
        let path = GMSMutablePath()
        line.coordinates.forEach { path.add(CLLocationCoordinate2D($0)) }
        func polyline(zIndex: Int32) -> GMSPolyline {
            let polyline = GMSPolyline(path: path)
            polyline.zIndex = zIndex
            return polyline
        }
        // Below the journey (1) and every other overlay (0) and marker.
        return Drawn(
            colors: line.colors.map(Self.color(hex:)),
            casing: polyline(zIndex: -2),
            stripes: line.colors.map { _ in polyline(zIndex: -1) }
        )
    }

    private func applyColors(_ line: Drawn, colorScheme: ColorScheme) {
        let isDark = colorScheme == .dark
        line.casing.strokeColor = isDark
            ? UIColor(white: 0.11, alpha: 0.9)
            : Self.mixed(line.colors[0], with: .black, 0.4)
        for (stripe, color) in zip(line.stripes, line.colors) {
            // Lighter on the dark map, where the browns and purples would sink into the roads.
            stripe.strokeColor = isDark ? Self.mixed(color, with: .white, 0.15) : color
        }
    }

    /// A single colour is `base` wide; several share it as concentric stripes, outermost first, in a wider line.
    private func applyWidths(_ line: Drawn, base: CGFloat) {
        let count = CGFloat(line.stripes.count)
        let width = base * (1 + 0.5 * (count - 1))
        line.casing.strokeWidth = width + 1.5
        for (index, stripe) in line.stripes.enumerated() {
            stripe.strokeWidth = width * (count - CGFloat(index)) / count
        }
    }

    /// A colour from `RRGGBB` hex; grey where it isn't valid.
    static func color(hex: String) -> UIColor {
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return .systemGray }
        return UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    /// `color` moved `amount` (0...1) of the way toward `other`.
    private static func mixed(_ color: UIColor, with other: UIColor, _ amount: CGFloat) -> UIColor {
        var (r1, g1, b1, a1) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
        var (r2, g2, b2, a2) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
        color.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(
            red: r1 + (r2 - r1) * amount,
            green: g1 + (g2 - g1) * amount,
            blue: b1 + (b2 - b1) * amount,
            alpha: 1
        )
    }
}
