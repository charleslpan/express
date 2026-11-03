import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// The MOTIS servers Express can talk to. Both serve the same API and the same dataset ids
/// (`us-ny-MTA-NYCSubway`, `us-ny-MTA-BusBrooklyn`, …), so switching is a matter of base URL alone.
public enum TransitServer: String, Sendable, CaseIterable {
    /// Express's own backend (the Vercel project `express-server`): NYC subway and buses with live data.
    case express
    /// Transitous's public instance, kept as a debug override.
    case transitous

    /// The server's root, without `/api`.
    public var baseURL: URL {
        switch self {
        case .express: URL(string: "https://express-server-cyan-zeta.vercel.app")!
        case .transitous: URL(string: "https://api.transitous.org")!
        }
    }
}
