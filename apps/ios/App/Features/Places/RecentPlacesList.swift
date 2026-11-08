import GlassUI
import SwiftUI
import TransitKit

/// The places you picked in search, newest first, under "Recents" with a Clear button: what place search shows
/// before you type, once there are any. Each row's name and address are fetched live by place ID (never stored);
/// tapping one shows the place as a pick from search would, through ``AppRouter/showPlace(_:)``, or hands it to
/// `onPick` where place search was opened to pick a journey's start or end.
struct RecentPlacesList: View {
    @Environment(AppRouter.self) private var router
    let store: PlaceStore
    /// What picking a recent does; nil shows it on the map.
    private let onPick: ((PlaceDetails) -> Void)?

    /// The recent being fetched before it's shown, while it is.
    @State private var opening: String?
    @State private var openFailed = false

    init(store: PlaceStore, onPick: ((PlaceDetails) -> Void)? = nil) {
        self.store = store
        self.onPick = onPick
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text("Recents")
                    .typography(.cardTitle)
                    .foregroundStyle(.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button("Clear", action: store.clearRecents)
                    .typography(.body)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Clear Recents")
                    .accessibilityIdentifier("search.recents.clear")
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(store.recents) { recent in
                    RecentPlaceRow(
                        entry: store.details.entries[recent.placeID],
                        isOpening: opening == recent.placeID,
                        action: { open(recent) }
                    )
                    .disabled(opening != nil)
                    .task { await store.details.load(recent.placeID) }
                    Divider()
                }
            }
        }
        .accessibilityElement(children: .contain)
        // "search.recents" once every row has its name, which the screenshot harness waits for.
        .accessibilityIdentifier(isLoaded ? "search.recents" : "search.recents.loading")
        .alert("Couldn't Open Place", isPresented: $openFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Google couldn't find this place just now. Try again in a moment.")
        }
    }

    private var isLoaded: Bool {
        store.recents.allSatisfy { recent in
            store.details.entries[recent.placeID].map { $0 != .loading } ?? false
        }
    }

    private func open(_ recent: RememberedPlace) {
        opening = recent.placeID
        Task {
            defer { opening = nil }
            guard let place = await store.details.load(recent.placeID) else {
                openFailed = true
                return
            }
            store.addRecent(place)
            if let onPick {
                onPick(place)
            } else {
                router.showPlace(place)
            }
        }
    }
}

/// One recent: a clock, the place's name and address once they've arrived (a placeholder until then), as one button.
private struct RecentPlaceRow: View {
    let entry: PlaceDetailsCache.Entry?
    let isOpening: Bool
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var gap = Spacing.sm

    var body: some View {
        Button(action: action) {
            HStack(spacing: gap) {
                Image(systemName: "clock.fill")
                    .font(.title2)
                    .foregroundStyle(.textSecondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxxs) {
                    Text(title)
                        .typography(.body)
                        .foregroundStyle(.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .typography(.secondary)
                            .foregroundStyle(.textSecondary)
                    }
                }
                .redacted(reason: isLoading ? .placeholder : [])
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
        .accessibilityLabel(Text([title, subtitle].compactMap(\.self).joined(separator: ", ")))
        .accessibilityValue(isOpening ? Text("Loading") : Text(""))
        .accessibilityAddTraits(.isButton)
    }

    private var isLoading: Bool {
        entry == nil || entry == .loading
    }

    private var title: String {
        switch entry {
        case let .loaded(place): place.name
        case .failed: String(localized: "Place unavailable")
        case .loading, nil: String(localized: "Loading place")
        }
    }

    private var subtitle: String? {
        switch entry {
        case let .loaded(place): place.address
        case .failed: String(localized: "Tap to try again")
        case .loading, nil: String(localized: "Loading address")
        }
    }
}

#Preview("Recents") {
    let store = PlaceStore.inMemory()
    store.addRecent(PlaceDetails(
        placeID: "preview-grand-army-plaza",
        name: "Grand Army Plaza",
        address: "Brooklyn, NY 11238, USA",
        coordinate: Coordinate(latitude: 40.6743, longitude: -73.9701)
    ))
    store.addRecent(PlaceDetails(
        placeID: "preview-grand-central-terminal",
        name: "Grand Central Terminal",
        address: "89 E 42nd St, New York, NY 10017, USA",
        coordinate: Coordinate(latitude: 40.7527, longitude: -73.9772)
    ))
    return RecentPlacesList(store: store)
        .padding()
        .environment(AppRouter(homeDetent: .full))
}
