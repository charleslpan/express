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
/// be glass itself. The field is at least 48 points tall and grows with Dynamic Type.
public struct GlassSearchField<Accessory: View>: View {
    private let prompt: LocalizedStringKey
    @Binding private var text: String
    private let onSubmit: () -> Void
    private let accessory: Accessory

    @FocusState private var isFocused: Bool
    @ScaledMetric(relativeTo: .body) private var minHeight = GlassMetrics.floatingControl
    @ScaledMetric(relativeTo: .body) private var gap = Spacing.xs

    /// A search field showing `prompt` while it's empty, which is also its VoiceOver label. `onSubmit` runs when the
    /// keyboard's Search key is tapped.
    public init(
        _ prompt: LocalizedStringKey,
        text: Binding<String>,
        onSubmit: @escaping () -> Void = {},
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.prompt = prompt
        _text = text
        self.onSubmit = onSubmit
        self.accessory = accessory()
    }

    public var body: some View {
        HStack(spacing: gap) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.textSecondary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .foregroundStyle(.textPrimary)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .focused($isFocused)
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
        .onTapGesture { isFocused = true }
        .glassSurface(in: Capsule(), isInteractive: true)
    }

    private var hasTrailingControl: Bool {
        !text.isEmpty || Accessory.self != EmptyView.self
    }
}

public extension GlassSearchField where Accessory == EmptyView {
    /// A search field showing `prompt` while it's empty, which is also its VoiceOver label. `onSubmit` runs when the
    /// keyboard's Search key is tapped.
    init(_ prompt: LocalizedStringKey, text: Binding<String>, onSubmit: @escaping () -> Void = {}) {
        self.init(prompt, text: text, onSubmit: onSubmit) { EmptyView() }
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
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(LinearGradient(colors: [.green, .blue], startPoint: .top, endPoint: .bottom))
}
