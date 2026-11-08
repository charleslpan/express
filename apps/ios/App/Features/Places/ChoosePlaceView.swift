import GlassUI
import SwiftUI
import TransitKit

/// Place search, pushed over the home sheet's sections to choose Home or Work (``AppRouter/choosePlace(for:)``):
/// picking a place, or one of your recents, makes it Home or Work and returns to the sections; Cancel leaves it as it
/// was.
struct ChoosePlaceView: View {
    let route: ChoosePlaceRoute

    @Environment(AppRouter.self) private var router
    @Environment(PlaceStore.self) private var store: PlaceStore?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(route.slot.chooseTitle)
                .typography(.sectionTitle)
                .foregroundStyle(.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.lg)
            PlaceSearchPanel(onPick: pick, onCancel: router.endChoosingPlace)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
        .accessibilityIdentifier("places.choose")
    }

    private func pick(_ place: PlaceDetails) {
        store?.set(route.slot, to: place)
        router.endChoosingPlace()
    }
}

extension PlaceSlot {
    var chooseTitle: LocalizedStringKey {
        switch self {
        case .home: "Choose Home"
        case .work: "Choose Work"
        }
    }
}
