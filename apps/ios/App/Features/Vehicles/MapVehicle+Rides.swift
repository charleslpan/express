import Foundation
import TransitKit

extension MapVehicle {
    /// The map's id for a bus, set apart from trains' trip ids.
    static func busID(_ id: String) -> String {
        "bus|\(id)"
    }

    /// A ride's bus at its GPS position, read by VoiceOver as "M15-SBS bus" (or "M15-SBS bus, heading northeast").
    init(ride: TrackedRide, bus: Bus, heading: Double?) {
        let name = String(localized: "\(ride.bullet.text) bus")
        self.init(
            id: Self.busID(bus.id),
            coordinate: bus.coordinate,
            bearing: heading,
            bullet: ride.bullet,
            accessibilityLabel: heading.map { String(localized: "\(name), heading \(Self.compassPoint($0))") } ?? name
        )
    }

    /// A ride's train at its estimated position, read by VoiceOver as "Q train to 14 St-Union Sq, estimated
    /// position".
    init(ride: TrackedRide, estimate: TrackedRide.EstimatedPosition) {
        let line = ride.bullet.shape == .diamond ? "\(ride.bullet.text) express" : ride.bullet.text
        let place = estimate.fromStop == estimate.toStop
            ? String(localized: "\(line) train at \(estimate.toStop)")
            : String(localized: "\(line) train to \(estimate.toStop)")
        self.init(
            id: ride.tripId,
            coordinate: estimate.coordinate,
            bearing: estimate.bearing,
            bullet: ride.bullet,
            accessibilityLabel: String(localized: "\(place), estimated position")
        )
    }

    /// The nearest of the eight compass points to a bearing, such as "northeast" for 40°.
    private static func compassPoint(_ bearing: Double) -> String {
        let points = [
            String(localized: "north"), String(localized: "northeast"), String(localized: "east"),
            String(localized: "southeast"), String(localized: "south"), String(localized: "southwest"),
            String(localized: "west"), String(localized: "northwest"),
        ]
        let index = Int((bearing / 45).rounded()) % points.count
        return points[(index + points.count) % points.count]
    }
}
