import SwiftUI

/// A search field in a floating glass capsule, as at the top of Apple Maps:
///
/// ```swift
/// GlassSearchField("Search for a place or address", text: $query) {
///     search(query)
/// }
/// ```
///
/// Tapping anywhere on the capsule focuses the field. Once there's text, a clear button appears at its end. An
/// optional `accessory` sits at the trailing end, such as an account button; it's inside the glass, so it must not
/// be glass itself. The field is at least 48 points tall and grows with Dynamic Type up to AX2.
///
/// Inside a sheet, which already brings glass, pass `surface: .inset` to draw the capsule as a fill instead (no glass
/// on glass). Pass `isFocused` to focus the field from outside, such as when a search screen appears.
public struct GlassSearchField<Accessory: View>: View {
    private let prompt: LocalizedStringKey
    @Binding private var text: String
    private let surface: SearchFieldSurface
    private let externalFocus: FocusState<Bool>.Binding?
    private let onSubmit: () -> Void
    private let accessory: Accessory

    @FocusState private var ownFocus: Bool
    @ScaledMetric(relativeTo: .body) private var minHeight = GlassMetrics.floatingControl
    @ScaledMetric(relativeTo: .body) private var gap = Spacing.xs

    /// A search field showing `prompt` while it's empty, which is also its VoiceOver label. `onSubmit` runs when the
    /// keyboard's Search key is tapped.
    public init(
        _ prompt: LocalizedStringKey,
        text: Binding<String>,
        surface: SearchFieldSurface = .glass,
        isFocused: FocusState<Bool>.Binding? = nil,
        onSubmit: @escaping () -> Void = {},
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.prompt = prompt
        _text = text
        self.surface = surface
        externalFocus = isFocused
        self.onSubmit = onSubmit
        self.accessory = accessory()
    }

    private var isFocused: FocusState<Bool>.Binding {
        externalFocus ?? $ownFocus
    }

    public var body: some View {
        HStack(spacing: gap) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.textSecondary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .typography(.body)
                .foregroundStyle(.textPrimary)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .focused(isFocused)
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.textSecondary)
                        .frame(minWidth: GlassMetrics.minimumTarget, minHeight: GlassMetrics.minimumTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
            accessory
        }
        .typography(.body)
        .padding(.leading, Spacing.md)
        // The clear button and the accessory bring their own 44-point targets, which pad the end themselves.
        .padding(.trailing, hasTrailingControl ? Spacing.xxs : Spacing.md)
        .frame(minHeight: max(minHeight, GlassMetrics.minimumTarget))
        .contentShape(Capsule())
        .onTapGesture { isFocused.wrappedValue = true }
        .modifier(SearchFieldBackground(surface: surface))
        // Past AX2 the icons crowd the field out of room for its text; the system's own search bars stop there too.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private var hasTrailingControl: Bool {
        !text.isEmpty || Accessory.self != EmptyView.self
    }
}

public extension GlassSearchField where Accessory == EmptyView {
    /// A search field showing `prompt` while it's empty, which is also its VoiceOver label. `onSubmit` runs when the
    /// keyboard's Search key is tapped.
    init(
        _ prompt: LocalizedStringKey,
        text: Binding<String>,
        surface: SearchFieldSurface = .glass,
        isFocused: FocusState<Bool>.Binding? = nil,
        onSubmit: @escaping () -> Void = {}
    ) {
        self.init(prompt, text: text, surface: surface, isFocused: isFocused, onSubmit: onSubmit) { EmptyView() }
    }
}

/// What a ``GlassSearchField`` is drawn on.
public enum SearchFieldSurface: Sendable {
    /// Interactive Liquid Glass, for a field floating over the map.
    case glass
    /// A quiet fill, for a field inside a sheet or other surface that already brings glass.
    case inset
}

private struct SearchFieldBackground: ViewModifier {
    let surface: SearchFieldSurface

    func body(content: Content) -> some View {
        switch surface {
        case .glass:
            content.glassSurface(in: Capsule(), isInteractive: true)
        case .inset:
            // A fill is opaque enough with Reduce Transparency on, so it needs no fallback of its own.
            content.background(.fill.tertiary, in: Capsule())
        }
    }
}

#Preview("Search field") {
    @Previewable @State var query = ""
    @Previewable @State var filled = "Union Sq"
    VStack(spacing: Spacing.md) {
        GlassSearchField("Search for a place or address", text: $query)
        GlassSearchField("Search for a place or address", text: $filled) {
            Image(systemName: "person.crop.circle.fill")
                .font(.title2)
                .foregroundStyle(.textSecondary)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Account")
        }
        GlassSearchField("Search for a place or address", text: $query)
            .environment(\.forcesOpaqueGlass, true)
        GlassSearchField("Search for a place or address", text: $filled, surface: .inset)
            .padding()
            .background(.background, in: Radius.shape(Radius.xl))
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(LinearGradient(colors: [.green, .blue], startPoint: .top, endPoint: .bottom))
}
