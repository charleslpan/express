import GlassUI
import SwiftUI
import TransitKit

/// The picked place in the home sheet, while its pin is on the map: its name and address, and a button that closes
/// it. It draws no glass of its own: the system sheet it sits in is the glass (no glass on glass).
///
/// Journeys (J1) and saved places (P1) add their buttons ("Directions", "Save") in the actions row under the name.
struct PlaceCard: View {
    let place: PlaceDetails
    let onClose: () -> Void

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
                // The actions row: Directions (J1), then the Save toggle and Home or Work menu (P1).
                AdaptiveStack(spacing: Spacing.xs) {
                    DirectionsButton(place: place)
                    PlaceCardActions(place: place)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.lg)
            .padding(.bottom, Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
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
