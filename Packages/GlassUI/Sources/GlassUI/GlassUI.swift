import SwiftUI

/// Shared Liquid Glass components and styles for Express.
///
/// GlassUI depends on SwiftUI only. It never imports TransitKit: views take
/// plain values, and the app maps transit models onto them.
public enum GlassUI {
    /// The package's version, bumped by hand when its public API changes.
    public static let version = "0.1.0"
}
