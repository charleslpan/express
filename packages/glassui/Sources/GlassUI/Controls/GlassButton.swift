import SwiftUI

/// How much a glass button stands out.
public enum GlassProminence: Sendable {
    /// Clear glass, for most actions.
    case standard
    /// Glass tinted with ``ShapeStyle/brand``, for the one primary action in a group.
    case prominent
}

/// A capsule button on Liquid Glass, for actions that float over the map, such as "Directions":
///
/// ```swift
/// GlassEffectContainer(spacing: Spacing.floatingInset) {
///     HStack(spacing: Spacing.floatingInset) {
///         GlassButton("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill",
///                     prominence: .prominent) { … }
///         GlassButton("Save", systemImage: "bookmark") { … }
///     }
/// }
/// ```
///
/// Its glass is interactive, it's at least 44 points tall, and its title is its VoiceOver label. With Reduce
/// Transparency on it's drawn opaque. For a button with only an icon, use ``GlassIconButton``.
public struct GlassButton: View {
    private let title: LocalizedStringKey
    private let systemImage: String?
    private let prominence: GlassProminence
    private let action: () -> Void

    /// A glass button titled `title`, with an SF Symbol before it if you name one.
    public init(
        _ title: LocalizedStringKey,
        systemImage: String? = nil,
        prominence: GlassProminence = .standard,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.prominence = prominence
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
            }
            .typography(.button)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .frame(minWidth: GlassMetrics.minimumTarget, minHeight: GlassMetrics.minimumTarget)
        }
        .buttonStyle(GlassControlStyle(shape: Capsule(), prominence: prominence))
    }
}

/// A round, icon-only button on Liquid Glass, the kind that floats over the map ("Show my location"):
///
/// ```swift
/// GlassIconButton("Show my location", systemImage: "location.fill") { … }
///     .glassEffectID("location", in: namespace)
/// ```
///
/// `title` is its VoiceOver label and what the large content viewer shows, so make it say what the button does. It's
/// 48 points across at the default text size, grows with Dynamic Type up to the first accessibility size, and past
/// that shows the large content viewer when held, as the system's own bar buttons do.
public struct GlassIconButton: View {
    private let title: LocalizedStringKey
    private let systemImage: String
    private let prominence: GlassProminence
    private let action: () -> Void

    @ScaledMetric(relativeTo: .title3) private var diameter = GlassMetrics.floatingControl

    /// A round glass button showing `systemImage`, labelled `title` for VoiceOver.
    public init(
        _ title: LocalizedStringKey,
        systemImage: String,
        prominence: GlassProminence = .standard,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.prominence = prominence
        self.action = action
    }

    public var body: some View {
        let side = max(diameter, GlassMetrics.minimumTarget)
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.system(.title3, weight: .semibold))
                .frame(width: side, height: side)
        }
        .buttonStyle(GlassControlStyle(shape: Circle(), prominence: prominence))
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityShowsLargeContentViewer()
    }
}

/// Draws a button's label on interactive glass in `shape`, or opaque with Reduce Transparency on.
struct GlassControlStyle<S: InsettableShape>: ButtonStyle {
    let shape: S
    let prominence: GlassProminence

    func makeBody(configuration: Configuration) -> some View {
        GlassControlLabel(configuration: configuration, shape: shape, prominence: prominence)
    }
}

private struct GlassControlLabel<S: InsettableShape>: View {
    let configuration: ButtonStyleConfiguration
    let shape: S
    let prominence: GlassProminence

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.forcesOpaqueGlass) private var forcesOpaqueGlass

    private var isProminent: Bool {
        prominence == .prominent && isEnabled
    }

    private var foreground: Color {
        if !isEnabled {
            return .textTertiary
        }
        return isProminent ? .white : .textPrimary
    }

    var body: some View {
        configuration.label
            .foregroundStyle(foreground)
            .contentShape(shape)
            .glassSurface(in: shape, tint: isProminent ? Color.brand : nil, isInteractive: isEnabled)
            // Interactive glass shows the press itself; the opaque fallback needs its own.
            .scaleEffect(configuration.isPressed && (reduceTransparency || forcesOpaqueGlass) ? 0.95 : 1)
    }
}

#Preview("Buttons") {
    VStack(spacing: Spacing.md) {
        GlassEffectContainer(spacing: Spacing.floatingInset) {
            HStack(spacing: Spacing.floatingInset) {
                GlassButton("Go", systemImage: "arrow.triangle.turn.up.right.diamond.fill", prominence: .prominent) {}
                GlassButton("Save", systemImage: "bookmark") {}
                GlassIconButton("Share", systemImage: "square.and.arrow.up") {}
            }
        }
        GlassButton("Unavailable") {}
            .disabled(true)
        GlassButton("Directions", prominence: .prominent) {}
            .environment(\.forcesOpaqueGlass, true)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(LinearGradient(colors: [.blue, .orange], startPoint: .top, endPoint: .bottom))
}
