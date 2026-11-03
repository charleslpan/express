import Foundation
import Observation

/// The app's data clients, live or fixture-backed, injected into the view tree with `.environment(_:)`.
///
/// Each data client a feature adds (trip planning, arrivals, vehicle positions, …) gets a property here, set to its
/// live implementation, or, when `fixtures` is set, to a fixture-backed one that returns that set's data without
/// touching the network. Views read clients from here rather than creating their own, so the screenshot harness can
/// show any screen on fixture data.
@MainActor
@Observable
final class AppEnvironment {
    /// The fixture set the clients are backed by; nil means live data.
    let fixtures: FixtureSet?

    init(fixtures: FixtureSet? = nil) {
        self.fixtures = fixtures
    }

    /// The current time: the fixture set's reference date when there is one, so screenshots are reproducible.
    var now: Date {
        fixtures?.referenceDate ?? .now
    }
}
