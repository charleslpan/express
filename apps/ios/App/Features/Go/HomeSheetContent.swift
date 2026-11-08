import GlassUI
import SwiftUI

/// What the home sheet shows over the map: the search field at the top, as in Apple Maps, then the Nearby section
/// (N1), whose nearest departures show at the sheet's peek, then slots that later tasks fill: the service alert chip
/// (A3), Home and Work (P2), and the Saved section (P2), which come into view as the sheet is pulled up.
///
/// It knows nothing of the sheet it sits in: it draws no glass (the system sheet brings it) and doesn't scroll; the
/// sheet's ``HomeSheet`` does that. The search field comes first, so it's what shows at the sheet's peek, with what
/// a slot marks with ``View/homeSheetPeekBoundary(_:)`` under it.
struct HomeSheetContent<Alert: View, Places: View, Nearby: View, Saved: View>: View {
    private let onSearch: () -> Void
    private let alert: Alert
    private let places: Places
    private let nearby: Nearby
    private let saved: Saved

    /// The sheet's content: `onSearch` runs when the search field is tapped (``AppRouter/showPlaceSearch()``), and
    /// each slot shows the view its feature provides.
    init(
        onSearch: @escaping () -> Void,
        @ViewBuilder alert: () -> Alert,
        @ViewBuilder places: () -> Places,
        @ViewBuilder nearby: () -> Nearby,
        @ViewBuilder saved: () -> Saved
    ) {
        self.onSearch = onSearch
        self.alert = alert()
        self.places = places()
        self.nearby = nearby()
        self.saved = saved()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HomeSearchField(action: onSearch)
                // Past AX2 the field would crowd the map out at the sheet's peek; the system's search bars stop
                // there too. Clamped from outside so the field's scaled height stops with its text.
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            nearby
            alert
            places
            saved
        }
        .padding(.horizontal, Spacing.md)
        .padding(.bottom, Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension HomeSheetContent where Alert == AlertChipPlaceholder, Places == SavedPlacesPlaceholder,
    Nearby == NearbySection, Saved == SavedSectionPlaceholder
{
    /// The sheet with each slot showing its feature, or its placeholder until A3 and P2 land.
    init(onSearch: @escaping () -> Void) {
        self.init(onSearch: onSearch) {
            AlertChipPlaceholder()
        } places: {
            SavedPlacesPlaceholder()
        } nearby: {
            NearbySection()
        } saved: {
            SavedSectionPlaceholder()
        }
    }
}

extension View {
    /// Marks the bottom of what the home sheet shows at its peek, such as the nearest station's second departure
    /// row: the peek grows to show the search field and everything down to this view. Where nothing is marked (or
    /// `isActive` is false everywhere), the peek shows the search field alone.
    func homeSheetPeekBoundary(_ isActive: Bool = true) -> some View {
        anchorPreference(key: HomePeekBoundary.self, value: .bounds) { isActive ? $0 : nil }
    }
}

/// The view that ends the home sheet's peek, from ``View/homeSheetPeekBoundary(_:)``; the first one marked wins.
struct HomePeekBoundary: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? {
        nil
    }

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// A search field that starts a search rather than taking text: tapping it hands over to place search. It's drawn
/// as a filled capsule rather than glass, since it sits inside the sheet's glass.
struct HomeSearchField: View {
    /// The field's height at the default text size, as in Apple Maps; it scales with Dynamic Type up to AX2.
    static let height: CGFloat = 48

    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var minHeight = HomeSearchField.height
    @ScaledMetric(relativeTo: .body) private var gap = Spacing.xs

    var body: some View {
        Button(action: action) {
            HStack(spacing: gap) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.textSecondary)
                Text("Search for a place or address")
                    .foregroundStyle(.textSecondary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .typography(.body)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
            .frame(maxWidth: .infinity, minHeight: max(minHeight, 44), alignment: .leading)
            .background(.fill.tertiary, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Search for a place or address")
        .accessibilityAddTraits(.isSearchField)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("home.search")
    }
}

#Preview("Home sheet content") {
    ScrollView {
        HomeSheetContent {}
            .padding(.top, Spacing.lg)
    }
    .environment(AppRouter())
    .environment(LocationService(fixed: .notDetermined))
    .environment(AppEnvironment())
}

#Preview("Home sheet content, AX5") {
    ScrollView {
        HomeSheetContent {}
            .padding(.top, Spacing.lg)
    }
    .dynamicTypeSize(.accessibility5)
    .environment(AppRouter())
    .environment(LocationService(fixed: .notDetermined))
    .environment(AppEnvironment())
}
