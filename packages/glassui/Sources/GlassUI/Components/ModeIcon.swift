import SwiftUI

/// A travel mode's SF Symbol, plain or on a tile in the mode's accent. It scales with Dynamic Type.
///
/// ```swift
/// ModeIcon(.walk)                  // a glyph in the current foreground style
/// ModeIcon(.bus, style: .tile)     // white on the bus accent
/// ```
public struct ModeIcon: View {
    /// How the icon is drawn.
    public enum Style: Sendable {
        /// The glyph alone, in the current foreground style.
        case glyph
        /// The glyph on a rounded tile in the mode's accent.
        case tile
    }

    private let mode: TravelMode
    private let style: Style
    @ScaledMetric(relativeTo: .subheadline) private var tileSize: CGFloat = 28

    public init(_ mode: TravelMode, style: Style = .glyph) {
        self.mode = mode
        self.style = style
    }

    public var body: some View {
        switch style {
        case .glyph:
            glyph
        case .tile:
            glyph
                .foregroundStyle(mode.onColor)
                .frame(width: tileSize, height: tileSize)
                .background(mode.color, in: Radius.shape(Radius.concentric(outer: Radius.sm, inset: 2)))
        }
    }

    private var glyph: some View {
        Image(systemName: mode.symbolName)
            .font(.system(.subheadline, weight: .semibold))
            .imageScale(.medium)
            .accessibilityLabel(mode.title)
    }
}

#if DEBUG
    private struct ModeIconPreview: View {
        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    ForEach(TravelMode.allCases) { ModeIcon($0) }
                }
                HStack(spacing: Spacing.xs) {
                    ForEach(TravelMode.allCases) { ModeIcon($0, style: .tile) }
                }
            }
            .padding()
        }
    }

    #Preview("ModeIcon") {
        ModeIconPreview()
    }

    #Preview("ModeIcon, dark") {
        ModeIconPreview()
            .preferredColorScheme(.dark)
    }

    #Preview("ModeIcon, AX5") {
        ModeIconPreview()
            .dynamicTypeSize(.accessibility5)
    }
#endif
