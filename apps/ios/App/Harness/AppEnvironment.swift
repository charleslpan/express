import Foundation
import Observation

/// The launch's fixture set and clock, injected into the view tree with `.environment(_:)`.
///
/// Data clients follow `fixtures`: when it is set, a client returns that set's data without touching the network.
/// `TransitClient` (the `\.transitClient` environment value, set in `ExpressApp`) is `FixtureSet.transitClient`
/// when `fixtures` is set, which answers each operation from the set's recorded responses: add a screen's responses
/// there. Views read clients and `now` from the environment rather than making their own, so the screenshot harness
/// can show any screen on fixture data.
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
