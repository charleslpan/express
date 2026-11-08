import GlassUI
import SwiftUI
import TransitKit

/// What a row of a remembered place says: your own label or Google's name, and the address, from its details as
/// they stand this session (``PlaceDetailsCache/Entry``), with placeholder text while they load.
struct RememberedPlaceText: Equatable {
    let title: String
    let subtitle: String?
    /// Whether the details are still on their way, so the row draws its text as a placeholder.
    let isLoading: Bool

    /// The text for a place whose details stand at `entry` (nil before anyone asked), titled `label` where you gave
    /// it one.
    init(entry: PlaceDetailsCache.Entry?, label: String? = nil) {
        switch entry {
        case let .loaded(place):
            title = label ?? place.name
            subtitle = place.address
            isLoading = false
        case .failed:
            title = label ?? String(localized: "Place unavailable")
            subtitle = String(localized: "Tap to try again")
            isLoading = false
        case .loading, nil:
            title = label ?? String(localized: "Loading place")
            subtitle = String(localized: "Loading address")
            isLoading = true
        }
    }
}

/// One remembered place, such as a recent or a saved place: its icon, then its name and address once they've arrived
/// (a placeholder until then), as one button.
struct RememberedPlaceRow: View {
    let systemImage: String
    let text: RememberedPlaceText
    let isOpening: Bool
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var gap = Spacing.sm

    var body: some View {
        Button(action: action) {
            HStack(spacing: gap) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(.textSecondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxxs) {
                    Text(text.title)
                        .typography(.body)
                        .foregroundStyle(.textPrimary)
                    if let subtitle = text.subtitle {
                        Text(subtitle)
                            .typography(.secondary)
                            .foregroundStyle(.textSecondary)
                    }
                }
                .redacted(reason: text.isLoading ? .placeholder : [])
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if isOpening {
                    ProgressView()
                }
            }
            .padding(.vertical, Spacing.sm)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text([text.title, text.subtitle].compactMap(\.self).joined(separator: ", ")))
        .accessibilityValue(isOpening ? Text("Loading") : Text(""))
        .accessibilityAddTraits(.isButton)
    }
}
