import GlassUI
import SwiftUI
import TransitKit

/// Place search in the home sheet, which ``AppRouter/showPlaceSearch()`` raises to full height: a search field with
/// Cancel, then Google's suggestions for New York as you type, with Google's attribution under them. Picking one
/// fetches its details and hands it to ``AppRouter/showPlace(_:)``, which pins it on the map.
///
/// Each state has its own view: a hint for an empty query, loading, no results, offline or failed with Try Again,
/// and "Search Unavailable" in a build with no Google Maps key.
struct PlaceSearchPanel: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.placeSearchService) private var service
    @Environment(\.placeSearchSeed) private var seed

    /// What picking a place does; nil shows it on the map with ``AppRouter/showPlace(_:)``.
    private let onPick: ((PlaceDetails) -> Void)?
    /// What Cancel does; nil ends the search with ``AppRouter/endPlaceSearch()``.
    private let onCancel: (() -> Void)?

    @State private var search: PlaceSearch?
    @FocusState private var isFieldFocused: Bool

    /// Place search. By default a picked place goes on the map; journeys pass `onPick` and `onCancel` to pick a start
    /// or an end instead.
    init(onPick: ((PlaceDetails) -> Void)? = nil, onCancel: (() -> Void)? = nil) {
        self.onPick = onPick
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            header
            ScrollView {
                if let search {
                    PlaceSearchResults(search: search, onPick: pick)
                        .padding(.bottom, Spacing.md)
                }
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.lg)
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear(perform: start)
        .alert(
            "Couldn't Open Place",
            isPresented: pickFailed,
            presenting: search?.pickError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.message)
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.xs) {
            GlassSearchField(
                "Search for a place or address",
                text: query,
                surface: .inset,
                isFocused: $isFieldFocused
            )
            .disabled(search?.status == .unavailable)
            .accessibilityIdentifier("search.field")
            Button("Cancel") {
                search?.reset()
                if let onCancel {
                    onCancel()
                } else {
                    router.endPlaceSearch()
                }
            }
            .typography(.body)
            .frame(minHeight: 44)
        }
        // Past AX2 the field would leave no room for results; the system's own search bars stop there too.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private var query: Binding<String> {
        Binding {
            search?.query ?? ""
        } set: { query in
            search?.update(query: query)
        }
    }

    private var pickFailed: Binding<Bool> {
        Binding {
            search?.pickError != nil && search?.picking == nil
        } set: { isPresented in
            if !isPresented {
                search?.dismissPickError()
            }
        }
    }

    private func start() {
        guard search == nil else { return }
        let search = PlaceSearch(service: service)
        self.search = search
        if let seed {
            search.update(query: seed)
        } else if search.status != .unavailable {
            isFieldFocused = true
        }
    }

    private func pick(_ suggestion: PlaceSuggestion) {
        guard let search else { return }
        Task {
            if let place = await search.pick(suggestion) {
                isFieldFocused = false
                if let onPick {
                    onPick(place)
                } else {
                    router.showPlace(place)
                }
            }
        }
    }
}

/// What place search shows under its field for each ``PlaceSearch/Status``.
private struct PlaceSearchResults: View {
    let search: PlaceSearch
    let onPick: (PlaceSuggestion) -> Void

    var body: some View {
        switch search.status {
        case .unavailable:
            ContentUnavailableView(
                "Search Unavailable",
                systemImage: "magnifyingglass",
                description: Text("This build of Express has no Google Maps key, so it can't search for places.")
            )
            .accessibilityIdentifier("search.unavailable")
        case .idle:
            ContentUnavailableView(
                "Where To?",
                systemImage: "magnifyingglass",
                description: Text("Search New York City for a place, an address, or a station.")
            )
            .accessibilityIdentifier("search.hint")
        case .loading:
            ProgressView("Searching…")
                .typography(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, Spacing.xl)
                .accessibilityIdentifier("search.loading")
        case let .results(suggestions):
            results(suggestions)
        case .noResults:
            VStack(spacing: Spacing.sm) {
                ContentUnavailableView.search(text: search.query)
                GoogleAttribution()
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("search.no-results")
        case let .failed(error):
            failure(error)
        }
    }

    private func results(_ suggestions: [PlaceSuggestion]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(suggestions) { suggestion in
                PlaceSuggestionRow(
                    suggestion: suggestion,
                    isLoading: search.picking == suggestion,
                    action: { onPick(suggestion) }
                )
                .disabled(search.picking != nil)
                Divider()
            }
            GoogleAttribution()
                .padding(.top, Spacing.sm)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("search.results")
    }

    private func failure(_ error: PlaceSearchError) -> some View {
        ContentUnavailableView {
            Label(error.title, systemImage: error.systemImage)
        } description: {
            Text(error.message)
        } actions: {
            Button("Try Again", action: search.retry)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .typography(.button)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("search.error")
    }
}

/// One suggestion: a pin, the place's name, and where it is, as one button.
private struct PlaceSuggestionRow: View {
    let suggestion: PlaceSuggestion
    let isLoading: Bool
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var gap = Spacing.sm

    var body: some View {
        Button(action: action) {
            HStack(spacing: gap) {
                Image(systemName: "mappin.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white, .brand)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxxs) {
                    Text(suggestion.title)
                        .typography(.body)
                        .foregroundStyle(.textPrimary)
                    if let subtitle = suggestion.subtitle {
                        Text(subtitle)
                            .typography(.secondary)
                            .foregroundStyle(.textSecondary)
                    }
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if isLoading {
                    ProgressView()
                }
            }
            .padding(.vertical, Spacing.sm)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text([suggestion.title, suggestion.subtitle].compactMap(\.self).joined(separator: ", ")))
        .accessibilityValue(isLoading ? Text("Loading") : Text(""))
        .accessibilityAddTraits(.isButton)
    }
}

/// Google's attribution under its results, which its terms require wherever Places results show. Text stands in for
/// the logo, as Google allows; the map under the sheet is Google's too.
private struct GoogleAttribution: View {
    var body: some View {
        Text(verbatim: "Google Maps")
            .typography(.captionEmphasized)
            .foregroundStyle(.textSecondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityLabel("Results from Google Maps")
    }
}

private extension PlaceSearchError {
    var title: LocalizedStringKey {
        switch self {
        case .offline: "You're Offline"
        case .unavailable: "Search Unavailable"
        case .failed: "Search Isn't Working"
        }
    }

    var systemImage: String {
        switch self {
        case .offline: "wifi.slash"
        case .unavailable: "magnifyingglass"
        case .failed: "exclamationmark.magnifyingglass"
        }
    }

    var message: LocalizedStringKey {
        switch self {
        case .offline: "Connect to the internet to search for places."
        case .unavailable: "Google turned down Express's key, so it can't search for places right now."
        case .failed: "Google couldn't answer just now. Try again in a moment."
        }
    }
}

#Preview("Search") {
    PlaceSearchPanel()
        .environment(AppRouter(homeDetent: .full))
        .environment(\.placeSearchService, FixturePlaceSearchService(fixtures: .nycEvening))
        .environment(\.placeSearchSeed, "Grand")
}

#Preview("Search unavailable") {
    PlaceSearchPanel()
        .environment(AppRouter(homeDetent: .full))
}
