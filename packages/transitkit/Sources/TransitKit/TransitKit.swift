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
    public static let version = "0.1.0"
}
