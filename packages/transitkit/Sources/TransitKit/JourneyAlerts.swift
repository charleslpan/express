import Foundation

// Alerts on a journey, warn-only: they never change the route. MOTIS attaches them to each ride leg (the line's) and to
// the places it boards and alights at (the stop's). A leg shows those that apply while the rider would be on it, by
// the leg's own times rather than "now", so planned work outside the trip never shows.

/// A stop where the rider boards or gets off that an alert says the leg's trains (or buses) skip, such as "Trains skip
/// 42 St".
public struct SkippedStop: Sendable, Hashable {
    public enum Role: Sendable, Hashable {
        /// Where the rider gets on.
        case board
        /// Where the rider gets off.
        case alight
    }

    public var role: Role
    /// The stop's name, as MOTIS gives it.
    public var name: String
    /// The alert that says so.
    public var alert: ServiceAlert

    public init(role: Role, name: String, alert: ServiceAlert) {
        self.role = role
        self.name = name
        self.alert = alert
    }
}

public extension ServiceAlert {
    /// Whether the alert, attached to a stop, says the stop is skipped or not served: a stops-skipped
    /// (`MODIFIED_SERVICE`) or suspension (`NO_SERVICE`) effect that reads as severe. Other stop alerts, such as an
    /// elevator outage, are only notices.
    var skipsStop: Bool {
        ["MODIFIED_SERVICE", "NO_SERVICE"].contains(effect) && level == .severe
    }
}

public extension Sequence<ServiceAlert> {
    /// The alerts active at any moment of `interval`, such as a leg from boarding to alighting, each once, the most
    /// severe first (feed order within a level).
    func active(during interval: DateInterval) -> [ServiceAlert] {
        uniqued().filter { $0.isActive(during: interval) }.sortedBySeverity()
    }
}

public extension Leg {
    /// When the rider would be on the leg, for its alerts: from its departure to its arrival, taking the earlier of
    /// the scheduled and live departure and the later of the two arrivals.
    var alertWindow: DateInterval {
        let start = min(startTime, scheduledStartTime)
        let end = max(endTime, scheduledEndTime, start)
        return DateInterval(start: start, end: end)
    }

    /// Every alert MOTIS attached to the leg, whatever its time: a ride's own and its boarding and alighting stops',
    /// a walk's own. A walk leaves its stops' alerts to the rides that board and alight there, so each shows once.
    var serviceAlerts: [ServiceAlert] {
        let attached = tripId == nil ? [alerts] : [alerts, from.alerts, to.alerts]
        return attached.flatMap { ($0 ?? []).map(ServiceAlert.init) }
    }

    /// The alerts that apply while the rider would be on the leg (``alertWindow``), each once, the most severe first.
    var applicableAlerts: [ServiceAlert] {
        serviceAlerts.active(during: alertWindow)
    }

    /// The ride's boarding and alighting stops that an alert applying on the leg says are skipped: one attached to
    /// that stop (not to the whole line) with a stops-skipped or suspension effect (``ServiceAlert/skipsStop``).
    /// Empty for a walk.
    var skippedStops: [SkippedStop] {
        guard tripId != nil else { return [] }
        let lineWide = Set((alerts ?? []).map { ServiceAlert($0).id })
        let window = alertWindow
        let stops: [(SkippedStop.Role, Place)] = [(.board, from), (.alight, to)]
        return stops.compactMap { role, place in
            let skipping = (place.alerts ?? []).map(ServiceAlert.init)
                .filter { !lineWide.contains($0.id) && $0.skipsStop }
                .active(during: window)
            return skipping.first.map { SkippedStop(role: role, name: place.name, alert: $0) }
        }
    }
}

/// A journey option's alert flag on the options list: the most severe alert that applies on any of its legs, and the
/// lines it's on, such as "Alert on the 7 train".
public struct JourneyAlertFlag: Sendable, Hashable {
    /// A line the journey rides with an alert at the flag's level.
    public struct Line: Sendable, Hashable {
        public var bullet: LineBullet
        public var mode: TransitMode

        public init(bullet: LineBullet, mode: TransitMode) {
            self.bullet = bullet
            self.mode = mode
        }
    }

    /// The most severe level among the alerts that apply on the journey's legs.
    public var level: AlertLevel
    /// The rides with an alert at ``level``, in journey order, each line once; empty where only a walk has one.
    public var lines: [Line]

    public init(level: AlertLevel, lines: [Line]) {
        self.level = level
        self.lines = lines
    }

    /// Whether a ride has a severe alert, such as a suspension: the journey may be affected. Alerts never reroute it.
    public var mayAffectJourney: Bool {
        level == .severe && !lines.isEmpty
    }
}

public extension Itinerary {
    /// The journey's alert flag: `nil` where no alert applies on any leg at the time the rider would be on it.
    var alertFlag: JourneyAlertFlag? {
        let legAlerts = legs.map { ($0, $0.applicableAlerts) }
        guard let level = legAlerts.flatMap(\.1).map(\.level).max() else { return nil }
        var lines: [JourneyAlertFlag.Line] = []
        for (leg, alerts) in legAlerts where alerts.contains(where: { $0.level == level }) {
            guard let bullet = leg.lineBullet else { continue }
            let line = JourneyAlertFlag.Line(bullet: bullet, mode: leg.mode)
            if !lines.contains(line) {
                lines.append(line)
            }
        }
        return JourneyAlertFlag(level: level, lines: lines)
    }
}
