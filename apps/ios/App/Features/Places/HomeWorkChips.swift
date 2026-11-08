import GlassUI
import SwiftUI
import TransitKit

/// What a Home or Work chip shows and does, from ``PlaceStore``: "Home" for a place that's set, which a tap plans a
/// journey to, or "Set Home" where none is, which a tap opens place search for.
struct HomeWorkChip: Identifiable, Equatable {
    let slot: PlaceSlot
    /// The place that's Home or Work; nil where none is set.
    let place: RememberedPlace?

    var id: PlaceSlot {
        slot
    }

    var isSet: Bool {
        place != nil
    }

    /// The chips the home sheet shows: Home, then Work.
    @MainActor
    static func chips(in store: PlaceStore) -> [HomeWorkChip] {
        [HomeWorkChip(slot: .home, place: store.home), HomeWorkChip(slot: .work, place: store.work)]
    }

    var title: String {
        switch (slot, isSet) {
        case (.home, true): String(localized: "Home")
        case (.work, true): String(localized: "Work")
        case (.home, false): String(localized: "Set Home")
        case (.work, false): String(localized: "Set Work")
        }
    }

    var systemImage: String {
        isSet ? slot.filledSystemImage : slot.systemImage
    }

    /// Where a tap plans a journey to: the place's live `details`, or, where they can't be fetched just now, its
    /// cached coordinate under the chip's title. Nil where the chip isn't set or neither is at hand.
    func destination(details: PlaceDetails?, cachedCoordinate: Coordinate?) -> PlaceDetails? {
        guard let place else { return nil }
        if let details {
            return details
        }
        return cachedCoordinate.map { PlaceDetails(placeID: place.placeID, name: title, coordinate: $0) }
    }
}

/// Home and Work, side by side under the departures peek (stacked where they don't fit): one tap on a chip that's set
/// shows journeys there from the current location (``AppRouter/showJourneys(toSavedPlace:)``), and one that isn't
/// ("Set Home") opens place search to choose it (``AppRouter/choosePlace(for:)``). Long-press a chip that's set to
/// change it or remove it. Drawn as bordered capsules, not glass: they sit in the sheet's glass.
struct HomeWorkChips: View {
    @Environment(AppRouter.self) private var router
    @Environment(PlaceStore.self) private var store: PlaceStore?

    /// The chip whose place is being fetched before journeys show, while it is.
    @State private var opening: PlaceSlot?
    /// The chip whose place couldn't be fetched, for the alert.
    @State private var failed: PlaceSlot?

    var body: some View {
        if let store {
            let chips = HomeWorkChip.chips(in: store)
            AdaptiveStack(spacing: Spacing.xs) {
                ForEach(chips) { chip in
                    button(for: chip, store: store)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("home.places")
            // Fetches the names live, for VoiceOver and so a tap needn't wait.
            .task(id: chips.compactMap(\.place?.placeID)) {
                for placeID in chips.compactMap(\.place?.placeID) {
                    await store.details.load(placeID)
                }
            }
            .alert("Couldn't Plan a Journey", isPresented: isFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Google couldn't find this place just now. Try again in a moment.")
            }
        }
    }

    private var isFailed: Binding<Bool> {
        Binding {
            failed != nil
        } set: { isPresented in
            if !isPresented {
                failed = nil
            }
        }
    }

    private func button(for chip: HomeWorkChip, store: PlaceStore) -> some View {
        Button {
            tap(chip, store: store)
        } label: {
            HStack(spacing: Spacing.xs) {
                Label(chip.title, systemImage: chip.systemImage)
                if opening == chip.slot {
                    ProgressView()
                }
            }
            .typography(.button)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .disabled(opening != nil)
        .contextMenu {
            if chip.isSet {
                Button(chip.slot.changeTitle, systemImage: "pencil") {
                    router.choosePlace(for: chip.slot)
                }
                Button(chip.slot.removeTitle, systemImage: "trash", role: .destructive) {
                    store.clear(chip.slot)
                }
            }
        }
        .accessibilityLabel(Text(chip.title))
        .accessibilityValue(Text(value(of: chip, store: store)))
        .accessibilityHint(chip.isSet ? Text("Shows journeys there from where you are") : Text("Chooses a place"))
        .accessibilityIdentifier("home.chip.\(chip.slot.rawValue)")
    }

    /// The place's name for VoiceOver, once it's here.
    private func value(of chip: HomeWorkChip, store: PlaceStore) -> String {
        guard let placeID = chip.place?.placeID else { return "" }
        return store.details.details(for: placeID)?.name ?? ""
    }

    private func tap(_ chip: HomeWorkChip, store: PlaceStore) {
        guard let place = chip.place else {
            router.choosePlace(for: chip.slot)
            return
        }
        opening = chip.slot
        Task {
            defer { opening = nil }
            let details = await store.details.load(place.placeID)
            let destination = chip.destination(
                details: details,
                cachedCoordinate: store.coordinate(for: place.placeID)
            )
            guard let destination else {
                failed = chip.slot
                return
            }
            router.showJourneys(toSavedPlace: destination)
        }
    }
}

extension PlaceSlot {
    var changeTitle: LocalizedStringKey {
        switch self {
        case .home: "Change Home"
        case .work: "Change Work"
        }
    }
}

#Preview("Home and Work") {
    let store = PlaceStore.inMemory()
    store.set(.home, to: PlaceDetails(
        placeID: "preview-grand-army-plaza",
        name: "Grand Army Plaza",
        address: "Brooklyn, NY 11238, USA",
        coordinate: Coordinate(latitude: 40.6743, longitude: -73.9701)
    ))
    return HomeWorkChips()
        .padding()
        .environment(AppRouter(homeDetent: .half))
        .environment(store)
}
