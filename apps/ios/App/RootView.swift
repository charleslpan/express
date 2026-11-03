import GlassUI
import SwiftUI
import TransitKit

/// A placeholder until the first feature lands under `App/Features/`.
struct RootView: View {
    var body: some View {
        ContentUnavailableView(
            "Express",
            systemImage: "tram.fill",
            description: Text("TransitKit \(TransitKit.version) · GlassUI \(GlassUI.version)")
        )
    }
}

#Preview {
    RootView()
}
