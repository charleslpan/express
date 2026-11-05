import GlassUI
import SwiftUI

/// What the home sheet shows over the map: the search field at the top, as in Apple Maps, then slots that later
/// tasks fill: the service alert chip (A3), Home and Work (P2), and the nearest departures (N1).
///
/// It knows nothing of the sheet it sits in, so it draws no glass of its own (the sheet brings it) and never scrolls
/// or sizes itself; its container does both. ``header`` is what shows at the sheet's peek detent, and ``body`` is
/// the header and the slots stacked, for a container that scrolls them together.
struct HomeSheetContent<Alert: View, Places: View, Departures: View>: View {
    private let onSearch: () -> Void
    private let alert: Alert
    private let places: Places
    private let departures: Departures

    /// The sheet's content: `onSearch` runs when the search field is tapped (``AppRouter/showPlaceSearch()``), and
    /// each slot shows the view its feature provides.
    init(
        onSearch: @escaping () -> Void,
        @ViewBuilder alert: () -> Alert,
        @ViewBuilder places: () -> Places,
        @ViewBuilder departures: () -> Departures
    ) {
        self.onSearch = onSearch
        self.alert = alert()
        self.places = places()
        self.departures = departures()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            header
            slots
        }
        .padding(.horizontal, Spacing.md)
        .padding(.bottom, Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The search field: the part of the sheet that shows when it's pulled down to its peek.
    var header: some View {
        HomeSearchField(action: onSearch)
    }

    private var slots: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            alert
            places
            departures
        }
    }
}

extension HomeSheetContent where Alert == AlertChipPlaceholder, Places == SavedPlacesPlaceholder,
    Departures == NearestDeparturesPlaceholder
{
    /// The sheet with every slot showing its placeholder, until A3, P2, and N1 land.
    init(onSearch: @escaping () -> Void) {
        self.init(onSearch: onSearch) {
            AlertChipPlaceholder()
        } places: {
            SavedPlacesPlaceholder()
        } departures: {
            NearestDeparturesPlaceholder()
        }
    }
}

/// A search field that starts a search rather than taking text: tapping it hands over to place search. It's drawn
/// as a filled capsule rather than glass, since it sits inside the sheet's glass.
private struct HomeSearchField: View {
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 48
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
        // Past AX2 the field would crowd out the map at the sheet's peek; the system's search bars stop there too.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
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
            .padding(.top, Spacing.md)
    }
}

#Preview("Home sheet content, AX5") {
    ScrollView {
        HomeSheetContent {}
            .padding(.top, Spacing.md)
    }
    .dynamicTypeSize(.accessibility5)
}
