import Foundation

public extension Leg {
    /// Whether realtime data moved this leg's departure or arrival (MOTIS's `realTime`).
    var isRealtime: Bool {
        realTime
    }

    /// How many whole minutes late (positive) or early (negative) the leg departs, rounded to the nearest minute.
    ///
    /// MOTIS sends no delay field, so this is `startTime - scheduledStartTime`; `nil` without realtime data.
    var departureDelayMinutes: Int? {
        guard realTime else { return nil }
        return Self.minutes(from: scheduledStartTime, to: startTime)
    }

    /// How many whole minutes late (positive) or early (negative) the leg arrives; `nil` without realtime data.
    var arrivalDelayMinutes: Int? {
        guard realTime else { return nil }
        return Self.minutes(from: scheduledEndTime, to: endTime)
    }

    /// Whole minutes from `now` until the leg departs, for "leaves in N min": rounded down, and negative once gone.
    func minutesUntilDeparture(from now: Date) -> Int {
        Int((startTime.timeIntervalSince(now) / 60).rounded(.down))
    }

    /// The name riders know the leg's line by: the route's short name ("L", "B57"), else its long name
    /// ("Babylon Branch", for LIRR, Metro-North, and the ferry), else the display name.
    var lineName: String? {
        [routeShortName, routeLongName, displayName].lazy.compactMap(\.self).first { !$0.isEmpty }
    }

    internal static func minutes(from scheduled: Date, to actual: Date) -> Int {
        Int((actual.timeIntervalSince(scheduled) / 60).rounded())
    }
}

public extension Place {
    /// Whether realtime data stands behind this place's departure (or, at a leg's end, its arrival).
    var isRealtime: Bool {
        let reason = departureTimestampReason ?? arrivalTimestampReason
        return reason.map { $0 != .noRtData && $0 != .inconsistentRt } ?? false
    }

    /// Minutes late (positive) or early (negative) at this place's departure; `nil` without realtime data.
    var departureDelayMinutes: Int? {
        guard let departure, let scheduledDeparture,
              departureTimestampReason.map({ $0 != .noRtData && $0 != .inconsistentRt }) ?? false
        else { return nil }
        return Leg.minutes(from: scheduledDeparture, to: departure)
    }

    /// Minutes late (positive) or early (negative) at this place's arrival; `nil` without realtime data.
    var arrivalDelayMinutes: Int? {
        guard let arrival, let scheduledArrival,
              arrivalTimestampReason.map({ $0 != .noRtData && $0 != .inconsistentRt }) ?? false
        else { return nil }
        return Leg.minutes(from: scheduledArrival, to: arrival)
    }
}

public extension Itinerary {
    /// Whole minutes from `now` until the itinerary sets off, for "leaves in N min": rounded down.
    func minutesUntilDeparture(from now: Date) -> Int {
        Int((startTime.timeIntervalSince(now) / 60).rounded(.down))
    }

    /// Whether any leg carries realtime data.
    var isRealtime: Bool {
        legs.contains(where: \.realTime)
    }

    /// The legs that ride transit, skipping walks and other street legs.
    var transitLegs: [Leg] {
        legs.filter { $0.tripId != nil }
    }
}
