import SwiftUI

/// Corner radii, in points. Draw every rounded shape with continuous corners, the squircle iOS uses, through
/// ``shape(_:)`` rather than a plain `RoundedRectangle(cornerRadius:)`:
///
/// ```swift
/// content
///     .padding(Spacing.cardPadding)
///     .background(.surface, in: Radius.shape(Radius.lg))
/// ```
///
/// Nested shapes stay **concentric**: an inner shape's radius is the outer radius minus the padding between them
/// (``concentric(outer:inset:)``), so the curves run parallel. For a view nested in a container whose shape SwiftUI
/// knows (the screen, a sheet, or a view with `.containerShape(_:)`), use SwiftUI's `ConcentricRectangle()`, which
/// works the radius out from its container. A panel floating near the screen's edge then follows the device's own
/// corners.
///
/// Pills, line badges, and buttons with fully round ends use `Capsule()`, not a radius.
public enum Radius {
    /// 6 pt: small tags and inline badges.
    public static let xs: CGFloat = 6
    /// 10 pt: compact controls, thumbnails, and icon tiles.
    public static let sm: CGFloat = 10
    /// 16 pt: rows, text fields, and buttons that aren't capsules.
    public static let md: CGFloat = 16
    /// 24 pt: cards.
    public static let lg: CGFloat = 24
    /// 34 pt: floating panels and sheets, close to the corners of a modern iPhone's screen.
    public static let xl: CGFloat = 34

    /// Every radius, smallest first, by its name: for the gallery and tests.
    public static let steps: [(name: String, value: CGFloat)] = [
        ("xs", xs), ("sm", sm), ("md", md), ("lg", lg), ("xl", xl),
    ]

    /// A rounded rectangle with continuous corners of `radius`.
    public static func shape(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    /// The radius of a shape inset by `inset` inside a shape with radius `outer`, so their corners stay
    /// concentric; never below zero.
    public static func concentric(outer: CGFloat, inset: CGFloat) -> CGFloat {
        max(outer - inset, 0)
    }
}
