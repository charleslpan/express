import GlassUI
import SwiftUI
import TransitKit

/// The picked place in the home sheet, while its pin is on the map: its name and address, and a button that closes
/// it. It draws no glass of its own: the system sheet it sits in is the glass (no glass on glass).
///
/// The actions row has "Directions" (J1) and "Save" (P1). Home and Work are set from their own chips, not here.
///
/// The card fits its content: it measures its content height into `height`, and the home sheet uses that as its one
/// detent while the card is showing (``AppRouter/isShowingPlaceCard``), so there's no empty space under the buttons
/// and no drag that cuts one off. A `.height` detent excludes the bottom safe area, which the sheet adds below it (the
/// CI screenshots showed a gap of exactly that inset when the card counted it too). Where the content is taller than
/// the screen, as at the largest text sizes, it scrolls.
struct PlaceCard: View {
    let place: PlaceDetails
    @Binding var height: CGFloat?
    let onClose: () -> Void

    init(place: PlaceDetails, height: Binding<CGFloat?> = .constant(nil), onClose: @escaping () -> Void) {
        self.place = place
        _height = height
        self.onClose = onClose
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    VStack(alignment: .leading, spacing: Spacing.xxxs) {
                        Text(place.name)
                            .typography(.sectionTitle)
                            .foregroundStyle(.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        if let address = place.address {
                            Text(address)
                                .typography(.secondary)
                                .foregroundStyle(.textSecondary)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Close", systemImage: "xmark", action: onClose)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                        .accessibilityIdentifier("place.close")
                }
                // The actions row: Directions (J1), then the Save toggle (P1).
                AdaptiveStack(spacing: Spacing.xs) {
                    DirectionsButton(place: place)
                    PlaceCardActions(place: place)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.lg)
            .padding(.bottom, Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.height.rounded(.up) } action: { contentHeight in
                // Whole points, so layout rounding doesn't move the sheet.
                if contentHeight > 0 {
                    height = contentHeight
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("place.card")
    }
}

#Preview("Place card") {
    PlaceCard(place: FixturePlaceSearchService.places[0]) {}
        .environment(AppRouter())
}

#Preview("Place card, AX5") {
    PlaceCard(place: FixturePlaceSearchService.places[0]) {}
        .environment(AppRouter())
        .dynamicTypeSize(.accessibility5)
}
