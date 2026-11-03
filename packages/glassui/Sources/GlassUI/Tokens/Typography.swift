import SwiftUI

/// The type roles, each a system text style, so every one scales with Dynamic Type. Set a role with
/// `View.typography(_:)` instead of a `.font(…)` literal:
///
/// ```swift
/// Text("Times Sq–42 St").typography(.cardTitle)
/// Text("4 min").typography(.time)
/// ```
///
/// Times and counts use monospaced digits, so a ticking countdown doesn't jiggle the layout.
public enum Typography: String, CaseIterable, Identifiable, Sendable {
    /// A screen's own title, where it isn't the navigation bar's.
    case screenTitle
    /// A section's heading on a screen or in a sheet.
    case sectionTitle
    /// The title of a card, row, or stop.
    case cardTitle
    /// Running text.
    case body
    /// Running text that needs weight, such as the important part of a direction.
    case bodyEmphasized
    /// Secondary text under a title, such as a stop's lines or a trip's summary.
    case secondary
    /// Small supporting text, such as a timestamp or a footnote.
    case caption
    /// Small text that needs weight, such as a status ("Delayed").
    case captionEmphasized
    /// A departure time or countdown in a row ("4 min", "18:42").
    case time
    /// The hero time on a trip or departure screen.
    case timeLarge
    /// The text in a line badge or mode chip ("A", "M15").
    case badge
    /// A button's title.
    case button

    public var id: Self {
        self
    }

    /// The role's font: a system text style, so it scales with Dynamic Type.
    public var font: Font {
        switch self {
        case .screenTitle: .system(.largeTitle, weight: .bold)
        case .sectionTitle: .system(.title2, weight: .bold)
        case .cardTitle: .system(.headline)
        case .body: .system(.body)
        case .bodyEmphasized: .system(.body, weight: .semibold)
        case .secondary: .system(.subheadline)
        case .caption: .system(.caption)
        case .captionEmphasized: .system(.caption, weight: .semibold)
        case .time: .system(.title3, design: .rounded, weight: .semibold).monospacedDigit()
        case .timeLarge: .system(.largeTitle, design: .rounded, weight: .bold).monospacedDigit()
        case .badge: .system(.subheadline, design: .rounded, weight: .bold)
        case .button: .system(.body, weight: .semibold)
        }
    }

    /// The text style the role scales with, for `@ScaledMetric(relativeTo:)` on sizes that sit beside its text.
    public var textStyle: Font.TextStyle {
        switch self {
        case .screenTitle, .timeLarge: .largeTitle
        case .sectionTitle: .title2
        case .cardTitle: .headline
        case .body, .bodyEmphasized, .button: .body
        case .secondary, .badge: .subheadline
        case .caption, .captionEmphasized: .caption
        case .time: .title3
        }
    }
}

public extension View {
    /// Sets the font of the text in this view to a GlassUI type role.
    func typography(_ role: Typography) -> some View {
        font(role.font)
    }
}
