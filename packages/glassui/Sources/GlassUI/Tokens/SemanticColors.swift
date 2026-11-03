import SwiftUI
import UIKit

/// Semantic colours, by what they're for rather than how they look. Each has a light and a dark variant, and the
/// system ones also follow Increase Contrast. Use them wherever a style is expected:
///
/// ```swift
/// Text("Delayed").foregroundStyle(.statusDelayed)
/// card.background(.surface, in: Radius.shape(Radius.lg))
/// ```
///
/// Line colours are not here: they come from the transit feed at runtime. Mode accents are on ``TravelMode``.
public extension ShapeStyle where Self == Color {
    // MARK: Backgrounds

    /// The screen's base, behind everything (where there's no map).
    static var canvas: Color {
        Color(uiColor: .systemBackground)
    }

    /// The base of a screen of grouped content, such as settings or the gallery.
    static var canvasGrouped: Color {
        Color(uiColor: .systemGroupedBackground)
    }

    /// An opaque card or row on ``canvasGrouped``; also the Reduce Transparency stand-in for glass.
    static var surface: Color {
        Color(uiColor: .secondarySystemGroupedBackground)
    }

    /// Something sitting on a ``surface``, such as a tile or a well inside a card.
    static var surfaceRaised: Color {
        Color(uiColor: .tertiarySystemGroupedBackground)
    }

    /// A hairline between rows or around a light swatch.
    static var separatorLine: Color {
        Color(uiColor: .separator)
    }

    // MARK: Text and icons

    /// Titles and body text.
    static var textPrimary: Color {
        Color(uiColor: .label)
    }

    /// Supporting text, such as a subtitle.
    static var textSecondary: Color {
        Color(uiColor: .secondaryLabel)
    }

    /// The least important text, such as a placeholder or a disabled label.
    static var textTertiary: Color {
        Color(uiColor: .tertiaryLabel)
    }

    // MARK: Brand and status

    /// Express's accent: the app's accent colour, for selection, links, and the primary action.
    static var brand: Color {
        .accentColor
    }

    /// Running on time, and the realtime indicator.
    static var statusOnTime: Color {
        Color(uiColor: .systemGreen)
    }

    /// Late or reduced service.
    static var statusDelayed: Color {
        Color(uiColor: .systemOrange)
    }

    /// Cancelled, suspended, or a disruption that changes the trip.
    static var statusDisrupted: Color {
        Color(uiColor: .systemRed)
    }

    /// Neutral information, such as planned work that doesn't affect this trip.
    static var statusInfo: Color {
        Color(uiColor: .systemBlue)
    }
}
