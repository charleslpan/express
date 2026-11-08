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
    public static let version = "0.4.0"

    /// The MOTIS server every ``TransitClient`` talks to unless told otherwise: Express's own backend.
    ///
    /// The single place the default changes. Debug builds of the app can pick ``TransitServer/transitous`` instead.
    public static let defaultBaseURL = TransitServer.express.baseURL

    /// Where the operators of a MOTIS server can reach Express's developers, sent in every `User-Agent`
    /// (Transitous's usage policy asks for it; our own server gets it too).
    public static let contactURL = "https://github.com/charleslpan/express"
}
