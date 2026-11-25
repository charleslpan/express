import GlassUI
import SwiftUI
import TransitKit

/// The place card's saved-place action: a Save toggle. ``PlaceCard`` puts it in its actions row; it draws nothing where
/// there's no ``PlaceStore``. Home and Work are set from their own chips and ``ChoosePlaceView``, not from the card.
struct PlaceCardActions: View {
    let place: PlaceDetails

    @Environment(PlaceStore.self) private var store: PlaceStore?

    var body: some View {
        if let store {
            saveToggle(store)
        }
    }

    private func saveToggle(_ store: PlaceStore) -> some View {
        let isSaved = store.isSaved(place.placeID)
        return Toggle(isOn: Binding {
            isSaved
        } set: { save in
            if save {
                store.save(place)
            } else {
                store.unsave(place.placeID)
            }
        }) {
            Label(isSaved ? "Saved" : "Save", systemImage: isSaved ? "bookmark.fill" : "bookmark")
                .typography(.button)
        }
        .toggleStyle(.button)
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .accessibilityLabel("Save")
        .accessibilityHint(isSaved ? "Removes the place from your saved places" : "Adds the place to your saved places")
        .accessibilityIdentifier("place.save")
    }
}

extension PlaceSlot {
    var title: LocalizedStringKey {
        switch self {
        case .home: "Home"
        case .work: "Work"
        }
    }

    var removeTitle: LocalizedStringKey {
        switch self {
        case .home: "Remove as Home"
        case .work: "Remove as Work"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .work: "briefcase"
        }
    }

    var filledSystemImage: String {
        "\(systemImage).fill"
    }
}
