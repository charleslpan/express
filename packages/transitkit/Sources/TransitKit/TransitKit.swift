import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Transit data, networking, and routing logic for Express.
///
/// TransitKit must stay platform-neutral: no UIKit, SwiftUI, or CoreLocation,
/// so that it builds and tests on Linux.
public enum TransitKit {
    /// The package's version, bumped by hand when its public API changes.
    public static let version = "0.2.0"

    /// The MOTIS server every ``TransitClient`` talks to unless told otherwise: Transitous's public instance.
    ///
    /// The single place the default changes when Express moves to its own server.
    public static let defaultBaseURL = URL(string: "https://api.transitous.org")!

    /// Where the operators of a MOTIS server can reach Express's developers, sent in every `User-Agent`
    /// as Transitous's usage policy asks.
    public static let contactURL = "https://github.com/charleslpan/express"
}
