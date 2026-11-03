import CoreGraphics

/// The spacing scale, in points, for padding, gaps between views, and insets. Use these instead of literals.
///
/// The steps follow a 4-point grid that doubles as it grows, so neighbouring steps stay visibly different:
///
/// ```swift
/// VStack(alignment: .leading, spacing: Spacing.xs) { … }
///     .padding(Spacing.cardPadding)
/// ```
///
/// The scale is fixed. Where a gap should grow with Dynamic Type (such as the space beside an icon that grows with
/// the text), wrap the step in `@ScaledMetric`: `@ScaledMetric private var gap = Spacing.xs`.
public enum Spacing {
    /// 2 pt: between tightly coupled lines, such as a title and its subtitle.
    public static let xxxs: CGFloat = 2
    /// 4 pt: between an icon and its label inside a compact control.
    public static let xxs: CGFloat = 4
    /// 8 pt: between related elements in a row or stack.
    public static let xs: CGFloat = 8
    /// 12 pt: between rows inside a card.
    public static let sm: CGFloat = 12
    /// 16 pt: the default padding inside cards and the screen's side margins.
    public static let md: CGFloat = 16
    /// 24 pt: between groups of content.
    public static let lg: CGFloat = 24
    /// 32 pt: between sections of a screen.
    public static let xl: CGFloat = 32
    /// 48 pt: around large, standalone content such as an empty state.
    public static let xxl: CGFloat = 48

    /// The side margin of a screen's content.
    public static let screenInset = md
    /// The padding inside a card or floating panel.
    public static let cardPadding = md
    /// The gap between a floating control and the edge of the screen or another floating control.
    public static let floatingInset = xs

    /// Every step of the scale, smallest first, by its name: for the gallery and tests.
    public static let steps: [(name: String, value: CGFloat)] = [
        ("xxxs", xxxs), ("xxs", xxs), ("xs", xs), ("sm", sm), ("md", md), ("lg", lg), ("xl", xl), ("xxl", xxl),
    ]
}
