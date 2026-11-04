import GlassUI
import SwiftUI
import UIKit

/// The friendly state for a screen that needs the location when Express may not use it: what's off, what still
/// works, and a way to Settings.
struct LocationDeniedView: View {
    let authorization: LocationService.Authorization

    @Environment(\.openURL) private var openURL

    var body: some View {
        ContentUnavailableView {
            Label("Location Is Off", systemImage: "location.slash")
        } description: {
            Text(message)
        } actions: {
            if authorization == .denied, let settings = URL(string: UIApplication.openSettingsURLString) {
                Button("Open Settings") {
                    openURL(settings)
                }
                .buttonStyle(.glassProminent)
                .accessibilityHint("Opens Express's settings, where you can let it use your location.")
            }
        }
        .scrollsWhenTooTall()
    }

    private var message: LocalizedStringKey {
        if authorization == .restricted {
            "Location access is restricted on this iPhone. You can still search for a place or pick one on the map."
        } else {
            """
            Express uses your location to find stops near you and plan trips from where you are. \
            You can still search for a place or pick one on the map.
            """
        }
    }
}

extension View {
    /// Shows the view as it is where it fits, and in a scroll view where it doesn't, such as a
    /// `ContentUnavailableView` with a button at the largest text sizes, so the button stays reachable.
    func scrollsWhenTooTall() -> some View {
        ViewThatFits(in: .vertical) {
            self
            ScrollView {
                self
            }
        }
    }
}

#Preview("Denied") {
    LocationDeniedView(authorization: .denied)
}

#Preview("Restricted") {
    LocationDeniedView(authorization: .restricted)
}
