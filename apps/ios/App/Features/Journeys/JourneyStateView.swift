import GlassUI
import SwiftUI
import TransitKit
import UIKit

/// A state the journey options show in place of options, with a way on. Buttons are filled rather than glass, since
/// they sit in the sheet's glass.
struct JourneyStateView<Actions: View>: View {
    private let title: LocalizedStringKey
    private let systemImage: String
    private let message: LocalizedStringKey
    private let identifier: String
    private let actions: Actions

    init(
        _ title: LocalizedStringKey,
        systemImage: String,
        message: LocalizedStringKey,
        identifier: String,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.systemImage = systemImage
        self.message = message
        self.identifier = identifier
        self.actions = actions()
    }

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            actions
                .buttonBorderShape(.capsule)
                .typography(.button)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

/// The journey options' states: none found, outside New York City, location off, and failed.
enum JourneyStates {
    static func noJourneys(onChangeTime: @escaping () -> Void) -> some View {
        JourneyStateView(
            "No Journeys Found",
            systemImage: "tram",
            message: "Express couldn't find a subway or bus journey then. Try another time or place.",
            identifier: "journeys.no-results"
        ) {
            Button("Change Time", action: onChangeTime)
        }
        .buttonStyle(.bordered)
    }

    /// `onChooseStart` offers a start inside the city, where the journey starts from the current location.
    static func outsideServiceArea(onChooseStart: (() -> Void)?) -> some View {
        JourneyStateView(
            "Outside New York City",
            systemImage: "map",
            message: "Express plans journeys within New York City for now.",
            identifier: "journeys.outside-area"
        ) {
            if let onChooseStart {
                Button("Choose a Start Place", action: onChooseStart)
            }
        }
        .buttonStyle(.borderedProminent)
    }

    static func locationOff(
        _ authorization: LocationService.Authorization,
        onChooseStart: @escaping () -> Void
    ) -> some View {
        JourneyStateView(
            "Location Is Off",
            systemImage: "location.slash",
            message: authorization == .restricted
                ? "Location access is restricted on this iPhone. Choose where to start instead."
                : "Choose where to start, or let Express use your location in Settings.",
            identifier: "journeys.location-off"
        ) {
            LocationOffActions(showsSettings: authorization == .denied, onChooseStart: onChooseStart)
        }
    }

    static func failed(_ error: TransitError, onRetry: @escaping () -> Void) -> some View {
        let isOffline = error == .offline
        return JourneyStateView(
            isOffline ? "You're Offline" : "Journeys Aren't Loading",
            systemImage: isOffline ? "wifi.slash" : "exclamationmark.triangle",
            message: isOffline
                ? "Connect to the internet to see journeys."
                : "Express's server couldn't answer just now. Try again in a moment.",
            identifier: "journeys.error"
        ) {
            Button("Try Again", action: onRetry)
        }
        .buttonStyle(.bordered)
    }
}

/// Choose a start place, and Open Settings where the rider turned the location off.
struct LocationOffActions: View {
    let showsSettings: Bool
    let onChooseStart: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: Spacing.xs) {
            Button("Choose a Start Place", action: onChooseStart)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("journeys.choose-start")
            if showsSettings, let settings = URL(string: UIApplication.openSettingsURLString) {
                Button("Open Settings") {
                    openURL(settings)
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Opens Express's settings, where you can let it use your location.")
            }
        }
    }
}
