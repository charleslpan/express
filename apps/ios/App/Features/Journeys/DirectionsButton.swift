import GlassUI
import SwiftUI
import TransitKit

/// The place card's Directions action: shows ways to get to the place by subway and bus. Filled rather than glass,
/// since it sits in the sheet's glass.
struct DirectionsButton: View {
    let place: PlaceDetails

    @Environment(AppRouter.self) private var router

    var body: some View {
        Button {
            router.showJourneys(to: place)
        } label: {
            Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                .typography(.button)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .accessibilityHint("Shows ways to get here by subway and bus")
        .accessibilityIdentifier("place.directions")
    }
}
