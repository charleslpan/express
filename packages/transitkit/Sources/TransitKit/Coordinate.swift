import Foundation
import Polyline

/// A point on Earth in degrees, without CoreLocation so it builds on Linux.
public struct Coordinate: Sendable, Hashable, Codable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public extension Place {
    /// Where the place is.
    var coordinate: Coordinate {
        Coordinate(latitude: lat, longitude: lon)
    }
}

public extension EncodedPolyline {
    /// The polyline's points, decoded at the precision the response states (6 for `v6` plan legs).
    ///
    /// Empty where the polyline is empty or doesn't decode.
    var coordinates: [Coordinate] {
        guard !points.isEmpty else { return [] }
        let polyline = Polyline(encodedPolyline: points, precision: pow(10, Double(precision)))
        return (polyline.coordinates ?? []).map { Coordinate(latitude: $0.latitude, longitude: $0.longitude) }
    }
}

public extension Leg {
    /// The leg's path, decoded from ``legGeometry``.
    var coordinates: [Coordinate] {
        legGeometry.coordinates
    }
}
