import SwiftUI

/// The app shell: the map home (``GoView``), with the home sheet over it and the sheets the ``AppRouter`` presents
/// above that. There's no tab bar: Nearby, Saved, and search live in the home sheet, as in Apple Maps. It reads the
/// router and the location service from the environment, which `ExpressApp` (or the screenshot harness) injects.
struct RootView: View {
    var body: some View {
        GoView()
    }
}

#Preview("Home") {
    RootView()
        .environment(AppRouter())
        .environment(LocationService(fixed: .notDetermined))
}

#Preview("About") {
    RootView()
        .environment(AppRouter(sheet: .about))
        .environment(LocationService(fixed: .authorized))
}
