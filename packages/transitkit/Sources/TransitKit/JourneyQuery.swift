import Foundation

/// One end of a journey the rider asks for: where they are now, or a place they picked.
public enum JourneyEndpoint: Sendable, Hashable {
    /// The device's location, resolved when the journey is planned.
    case currentLocation
    /// A place picked from search.
    case place(PlaceDetails)

    /// Whether this end is the device's location, which needs location permission and a fix to plan from.
    public var isCurrentLocation: Bool {
        self == .currentLocation
    }
}

/// Why a ``JourneyQuery`` can't become a ``PlanRequest`` yet.
public enum JourneyQueryError: Error, Sendable, Equatable {
    /// One end is the current location, and the device hasn't given a fix (yet).
    case locationUnknown
    /// One end lies outside the area Express serves.
    case outsideServiceArea
}

/// The journey a rider asks for: from where, to where, and when, as the journey options screen holds it.
///
/// ```swift
/// var query = JourneyQuery(to: .place(grandCentral))          // from here, leaving now
/// query.time = .arriveBy(nineAM)
/// let request = try query.planRequest(currentLocation: here)
/// ```
public struct JourneyQuery: Sendable, Hashable {
    /// The transit modes Express plans with in v1: the subway and MTA buses, Select Bus Service and express buses
    /// included. The Staten Island Railway comes in the subway's feed but MOTIS calls it regional rail, so that mode
    /// is allowed too; Express's server loads no other railway.
    public static let transitModes: [TransitMode] = [.subway, .bus, .regionalRail]

    /// How many itineraries to ask MOTIS for: a sensible choice without a long list.
    public static let numberOfItineraries = 5

    public var from: JourneyEndpoint
    public var to: JourneyEndpoint
    public var time: PlanRequest.Time

    /// A journey from `from` (the current location by default) to `to`, leaving now unless `time` says otherwise.
    public init(from: JourneyEndpoint = .currentLocation, to: JourneyEndpoint, time: PlanRequest.Time = .now) {
        self.from = from
        self.to = to
        self.time = time
    }

    /// Whether either end is the current location.
    public var needsCurrentLocation: Bool {
        from.isCurrentLocation || to.isCurrentLocation
    }

    /// Swaps the two ends.
    public mutating func swapEnds() {
        swap(&from, &to)
    }

    /// The MOTIS request for this journey: subway and buses with walking, at ``time``.
    ///
    /// - Parameters:
    ///   - currentLocation: The device's latest fix, which stands in for ``JourneyEndpoint/currentLocation``.
    ///   - serviceArea: The area both ends must lie in.
    /// - Throws: ``JourneyQueryError/locationUnknown`` where an end is the current location and there's no fix;
    ///   ``JourneyQueryError/outsideServiceArea`` where either end lies outside `serviceArea`.
    public func planRequest(
        currentLocation: Coordinate?,
        serviceArea: ServiceArea = .nyc
    ) throws(JourneyQueryError) -> PlanRequest {
        let start = try Self.coordinate(of: from, currentLocation: currentLocation)
        let end = try Self.coordinate(of: to, currentLocation: currentLocation)
        guard serviceArea.contains(start), serviceArea.contains(end) else {
            throw .outsideServiceArea
        }
        return PlanRequest(
            from: .coordinate(start),
            to: .coordinate(end),
            time: time,
            transitModes: Self.transitModes,
            numberOfItineraries: Self.numberOfItineraries
        )
    }

    private static func coordinate(
        of endpoint: JourneyEndpoint,
        currentLocation: Coordinate?
    ) throws(JourneyQueryError) -> Coordinate {
        switch endpoint {
        case let .place(place):
            return place.coordinate
        case .currentLocation:
            guard let currentLocation else { throw .locationUnknown }
            return currentLocation
        }
    }
}
