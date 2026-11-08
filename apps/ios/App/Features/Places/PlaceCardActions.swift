import GlassUI
import SwiftUI
import TransitKit

/// The place card's saved-place actions: a Save toggle, and a menu that sets the place as Home or Work (or takes
/// it off). ``PlaceCard`` puts them in its actions row; they draw nothing where there's no ``PlaceStore``.
struct PlaceCardActions: View {
    let place: PlaceDetails

    @Environment(PlaceStore.self) private var store: PlaceStore?

    var body: some View {
        if let store {
            saveToggle(store)
            slotMenu(store)
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

    private func slotMenu(_ store: PlaceStore) -> some View {
        let current = store.slot(of: place.placeID)
        return Menu {
            ForEach(PlaceSlot.allCases) { slot in
                if slot == current {
                    Button(slot.removeTitle, systemImage: slot.systemImage, role: .destructive) {
                        store.clear(slot)
                    }
                } else {
                    Button(slot.setTitle, systemImage: slot.systemImage) {
                        store.set(slot, to: place)
                    }
                }
            }
        } label: {
            Label(current?.title ?? "Home or Work", systemImage: current?.filledSystemImage ?? "house")
                .typography(.button)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .accessibilityLabel("Home or Work")
        .accessibilityValue(current.map { Text($0.title) } ?? Text("Not set"))
        .accessibilityIdentifier("place.slots")
    }
}

extension PlaceSlot {
    var title: LocalizedStringKey {
        switch self {
        case .home: "Home"
        case .work: "Work"
        }
    }

    var setTitle: LocalizedStringKey {
        switch self {
        case .home: "Set as Home"
        case .work: "Set as Work"
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
