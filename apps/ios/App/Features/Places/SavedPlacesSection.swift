import GlassUI
import SwiftUI
import TransitKit
import UIKit

/// One row of the Saved section: a saved place and what its row says as its details stand this session.
struct SavedPlaceItem: Identifiable, Equatable {
    let placeID: String
    let text: RememberedPlaceText

    var id: String {
        placeID
    }

    /// The Saved section's rows: every saved place in the order you saved them (``PlaceStore/saved``), titled with
    /// your label where you gave one. Home and Work show here only where they're saved too.
    @MainActor
    static func items(in store: PlaceStore) -> [SavedPlaceItem] {
        store.saved.map { place in
            SavedPlaceItem(
                placeID: place.placeID,
                text: RememberedPlaceText(entry: store.details.entries[place.placeID], label: place.label)
            )
        }
    }
}

/// The home sheet's Saved section, below More Nearby: your saved places with their names and addresses, fetched live
/// by place ID (never stored), each with a placeholder while it loads. Tap one to show its card
/// (``AppRouter/showPlace(_:)``); swipe it left, or long-press it, to unsave it. With nothing saved, it says how to
/// save a place.
struct SavedPlacesSection: View {
    @Environment(AppRouter.self) private var router
    @Environment(PlaceStore.self) private var store: PlaceStore?

    /// The place being fetched before its card shows, while it is.
    @State private var opening: String?
    @State private var openFailed = false

    var body: some View {
        if let store {
            let items = SavedPlaceItem.items(in: store)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HomeSectionHeading("Saved")
                    .accessibilityIdentifier("home.saved.heading")
                if items.isEmpty {
                    empty
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(items) { item in
                            row(item, store: store)
                            Divider()
                        }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            // The screenshot harness waits for "home.saved" (every row loaded), "home.saved.loading", or
            // "home.saved.empty".
            .accessibilityIdentifier(identifier(for: items))
            .alert("Couldn't Open Place", isPresented: $openFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Google couldn't find this place just now. Try again in a moment.")
            }
        }
    }

    private var empty: some View {
        Label {
            Text("Tap Save on a place's card to keep it here, one tap from the map.")
        } icon: {
            Image(systemName: "bookmark")
                .accessibilityHidden(true)
        }
        .typography(.secondary)
        .foregroundStyle(.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, Spacing.xs)
    }

    private func row(_ item: SavedPlaceItem, store: PlaceStore) -> some View {
        RememberedPlaceRow(
            systemImage: "bookmark.fill",
            text: item.text,
            isOpening: opening == item.placeID,
            action: { open(item.placeID, store: store) }
        )
        .disabled(opening != nil)
        .modifier(SwipeToUnsave { withAnimation(.snappy) { store.unsave(item.placeID) } })
        .contextMenu {
            Button("Remove from Saved", systemImage: "bookmark.slash", role: .destructive) {
                store.unsave(item.placeID)
            }
        }
        .task { await store.details.load(item.placeID) }
    }

    private func identifier(for items: [SavedPlaceItem]) -> String {
        if items.isEmpty {
            return "home.saved.empty"
        }
        return items.contains(where: \.text.isLoading) ? "home.saved.loading" : "home.saved"
    }

    private func open(_ placeID: String, store: PlaceStore) {
        opening = placeID
        Task {
            defer { opening = nil }
            guard let place = await store.details.load(placeID) else {
                openFailed = true
                return
            }
            router.showPlace(place)
        }
    }
}

/// Swipe a row left to reveal Unsave, and keep swiping to unsave it at once, as in a list; VoiceOver offers Unsave as
/// an action. The home sheet's sections sit in a scroll view rather than a `List`, so this brings the list's swipe:
/// its pan begins only on a horizontal drag, leaving vertical ones to the scroll view and the sheet.
private struct SwipeToUnsave: ViewModifier {
    let onUnsave: () -> Void

    @State private var offset: CGFloat = 0
    @State private var isOpen = false
    @ScaledMetric(relativeTo: .body) private var actionWidth: CGFloat = 88

    func body(content: Content) -> some View {
        content
            // While Unsave shows, a tap on the row closes it rather than opening the place.
            .overlay {
                if isOpen {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { settle(open: false) }
                        .accessibilityHidden(true)
                }
            }
            .offset(x: offset)
            .background(alignment: .trailing) {
                if offset < 0 {
                    Button(role: .destructive, action: onUnsave) {
                        Label("Unsave", systemImage: "bookmark.slash.fill")
                            .labelStyle(.iconOnly)
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .buttonStyle(.plain)
                    .frame(width: -offset)
                    .frame(maxHeight: .infinity)
                    .background(.red)
                    .accessibilityHidden(true)
                }
            }
            .clipped()
            .gesture(HorizontalPan(onChange: drag, onEnd: end))
            .accessibilityAction(named: "Unsave", onUnsave)
    }

    private func drag(_ translation: CGFloat) {
        offset = min(0, (isOpen ? -actionWidth : 0) + translation)
    }

    private func end(_ translation: CGFloat, velocity: CGFloat) {
        let position = min(0, (isOpen ? -actionWidth : 0) + translation)
        if position < -actionWidth * 2.5 || (position < -actionWidth && velocity < -1500) {
            offset = 0
            isOpen = false
            onUnsave()
        } else {
            settle(open: position < -actionWidth / 2 && velocity < 500)
        }
    }

    private func settle(open: Bool) {
        withAnimation(.snappy) {
            isOpen = open
            offset = open ? -actionWidth : 0
        }
    }
}

/// A pan that begins only where the drag is more sideways than up or down, reporting its horizontal translation.
private struct HorizontalPan: UIGestureRecognizerRepresentable {
    let onChange: (CGFloat) -> Void
    let onEnd: (_ translation: CGFloat, _ velocity: CGFloat) -> Void

    func makeCoordinator(converter _: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context _: Context) {
        let translation = recognizer.translation(in: recognizer.view).x
        switch recognizer.state {
        case .changed:
            onChange(translation)
        case .ended:
            onEnd(translation, recognizer.velocity(in: recognizer.view).x)
        case .cancelled, .failed:
            onEnd(0, 0)
        default:
            break
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }
    }
}

#Preview("Saved") {
    let store = PlaceStore.inMemory()
    store.save(PlaceDetails(
        placeID: "preview-grand-central-terminal",
        name: "Grand Central Terminal",
        address: "89 E 42nd St, New York, NY 10017, USA",
        coordinate: Coordinate(latitude: 40.7527, longitude: -73.9772)
    ))
    return ScrollView {
        SavedPlacesSection()
            .padding()
    }
    .environment(AppRouter(homeDetent: .full))
    .environment(store)
}

#Preview("Saved, empty") {
    SavedPlacesSection()
        .padding()
        .environment(AppRouter(homeDetent: .full))
        .environment(PlaceStore.inMemory())
}
