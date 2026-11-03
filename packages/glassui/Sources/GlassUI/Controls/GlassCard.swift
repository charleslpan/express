import SwiftUI

/// A panel on Liquid Glass that floats over the map, such as a selected stop's summary:
///
/// ```swift
/// GlassCard {
///     Text("14 St–Union Sq").typography(.cardTitle)
///     Text("4 5 6 L N Q R W").typography(.secondary).foregroundStyle(.textSecondary)
/// }
/// ```
///
/// Its content stacks vertically, leading-aligned, with ``Spacing/cardPadding`` around it, in a ``Radius/lg`` shape.
/// Give it an `action` and the whole card becomes one button on interactive glass, which VoiceOver reads as one
/// element. Put plain content inside, never another glass view (no glass on glass): float glass buttons beside
/// the card rather than in it. Content that belongs in a sheet goes in a system sheet, which brings its own glass.
public struct GlassCard<Content: View>: View {
    private let action: (() -> Void)?
    private let content: Content

    /// A card showing `content`.
    public init(@ViewBuilder content: () -> Content) {
        action = nil
        self.content = content()
    }

    /// A card showing `content` that runs `action` when tapped.
    public init(action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.action = action
        self.content = content()
    }

    public var body: some View {
        if let action {
            Button(action: action) {
                card(isInteractive: true)
            }
            .buttonStyle(.plain)
        } else {
            card(isInteractive: false)
        }
    }

    private func card(isInteractive: Bool) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxxs) {
            content
        }
        .padding(Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Radius.shape(Radius.lg))
        .glassSurface(in: Radius.shape(Radius.lg), isInteractive: isInteractive)
    }
}

#Preview("Card") {
    VStack(spacing: Spacing.md) {
        GlassCard {
            Text("14 St–Union Sq").typography(.cardTitle)
            Text("4 5 6 L N Q R W · 2 min walk").typography(.secondary).foregroundStyle(.textSecondary)
        }
        GlassCard(action: {}) {
            Text("Tappable").typography(.cardTitle)
            Text("The whole card is one button").typography(.secondary).foregroundStyle(.textSecondary)
        }
        GlassCard {
            Text("Reduce Transparency").typography(.cardTitle)
        }
        .environment(\.forcesOpaqueGlass, true)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(LinearGradient(colors: [.orange, .purple], startPoint: .top, endPoint: .bottom))
}
