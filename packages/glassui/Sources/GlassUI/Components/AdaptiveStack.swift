import SwiftUI

/// Lays its subviews out side by side where they fit the width they're offered, and stacks them vertically where
/// they don't, such as a row of buttons or chips at accessibility text sizes:
///
/// ```swift
/// AdaptiveStack(spacing: Spacing.xs) {
///     Button("Home", systemImage: "house.fill") { … }
///     Button("Work", systemImage: "briefcase.fill") { … }
/// }
/// ```
///
/// It measures the row at its ideal width rather than relying on text shrinking to fit, which doesn't take for
/// capsule buttons inside a `GlassEffectContainer`; so a row never runs off the screen, whatever the text size or
/// language. Wrap a row of glass controls in the container from outside: `GlassEffectContainer { AdaptiveStack { … }
/// }`.
public struct AdaptiveStack<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    /// A row of `content` with `spacing` between, which becomes a leading-aligned column where it doesn't fit.
    public init(spacing: CGFloat = Spacing.xs, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: spacing) {
                content
            }
            VStack(alignment: .leading, spacing: spacing) {
                content
            }
        }
    }
}

#Preview("AdaptiveStack") {
    VStack(alignment: .leading, spacing: Spacing.lg) {
        AdaptiveStack {
            Button("Home", systemImage: "house.fill") {}
            Button("Work", systemImage: "briefcase.fill") {}
        }
        AdaptiveStack {
            Button("Home", systemImage: "house.fill") {}
            Button("Work", systemImage: "briefcase.fill") {}
        }
        .dynamicTypeSize(.accessibility5)
    }
    .buttonStyle(.bordered)
    .buttonBorderShape(.capsule)
    .padding()
}
