import Foundation

// Service alerts, warn-only: what MOTIS attaches to departures and legs (`place.alerts`) and what the line status
// endpoint (`/api/alerts`, ``TransitClient/lineStatus(lines:)``) returns, as one model, with the rule for when one
// applies. The feeds carry every alert they know of, planned work weeks away included, so a screen shows an alert
// only while it's active: at the departure's time on a departure, at "now" anywhere else.

/// A span of time an alert is active in. Either end may be open.
///
/// As in GTFS-RT, the span includes its start and excludes its end: an alert ending at midnight no longer applies to
/// a train leaving at midnight.
public struct AlertPeriod: Sendable, Hashable {
    /// When the alert starts to apply; `nil` for "since before anyone can remember".
    public var start: Date?
    /// When it stops applying; `nil` for "until further notice".
    public var end: Date?

    public init(start: Date?, end: Date?) {
        self.start = start
        self.end = end
    }

    /// Whether `date` falls inside the period: at or after its start, and before its end.
    public func contains(_ date: Date) -> Bool {
        if let start, date < start {
            return false
        }
        if let end, date >= end {
            return false
        }
        return true
    }

    /// Whether the period shares any moment with `interval`, such as a ride from boarding to alighting.
    public func overlaps(_ interval: DateInterval) -> Bool {
        guard interval.duration > 0 else { return contains(interval.start) }
        // A ride that ends the instant the period starts doesn't share a moment with it.
        if let start, interval.end <= start {
            return false
        }
        if let end, interval.start >= end {
            return false
        }
        return true
    }
}

/// How much an alert matters to a rider, which sets its colour and icon: suspensions and skipped stops are
/// ``severe`` (red), delays, reroutes, and reduced service ``warning`` (amber), and every other notice ``info``
/// (neutral).
public enum AlertLevel: Int, Sendable, Hashable, Comparable, CaseIterable {
    case info
    case warning
    case severe

    /// The level for an alert's GTFS-RT effect (`NO_SERVICE`, `SIGNIFICANT_DELAYS`, …) and, where known, its severity
    /// level (`INFO`, `WARNING`, `SEVERE`): the one rule every screen colours alerts by.
    ///
    /// Our server fills the effect and severity from the MTA's alert type ("Stops Skipped" becomes `MODIFIED_SERVICE`
    /// and `WARNING`, "Express to Local" `MODIFIED_SERVICE` and `INFO`). A modified service reads as severe unless the
    /// severity says it's only information. Line status carries the severity; on departures and legs it comes from
    /// the type MOTIS passes on (``MTAAlertType/severity(of:)``), and without one a modified service reads as severe.
    /// An effect this doesn't know, or none, is a neutral notice.
    public init(effect: String?, severity: String? = nil) {
        switch effect {
        case "NO_SERVICE":
            self = .severe
        case "MODIFIED_SERVICE":
            self = severity == "INFO" ? .info : .severe
        case "SIGNIFICANT_DELAYS", "DETOUR", "REDUCED_SERVICE":
            self = .warning
        default:
            self = .info
        }
    }

    public static func < (lhs: AlertLevel, rhs: AlertLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A service alert on a line, such as "[L] trains are running with delays", from either source.
public struct ServiceAlert: Sendable, Hashable, Identifiable {
    /// The MTA's alert id where the source gives one (line status does); else one made from the alert's text and
    /// times, the same for the same alert on every departure.
    public var id: String
    /// The MTA's own alert type ("Planned - Part Suspended"), where the source gives one: line status does, and MOTIS
    /// does as the alert's `effectDetail`, which our server fills with it.
    public var type: String?
    /// The GTFS-RT effect, such as `NO_SERVICE`; `nil` where the source gives none.
    public var effect: String?
    /// The GTFS-RT severity level, such as `WARNING`: line status's, or on departures and legs, which MOTIS gives
    /// none, the one ``MTAAlertType`` gives the type. `nil` where neither is known.
    public var severity: String?
    /// Whether it's planned work (the MTA's "Planned - …" types, which our server gives the `MAINTENANCE` cause).
    public var isPlanned: Bool
    /// When it applies; empty for "for as long as it's in the feed".
    public var activePeriods: [AlertPeriod]
    /// The short text, as the MTA wrote it; the MTA writes lines as `[A]`.
    public var header: String
    /// The full text, as the MTA wrote it, where there's more than the header.
    public var description: String?

    public init(
        id: String? = nil,
        type: String? = nil,
        effect: String?,
        severity: String? = nil,
        isPlanned: Bool,
        activePeriods: [AlertPeriod],
        header: String,
        description: String?
    ) {
        let description = description.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        self.id = id ?? Self.id(header: header, description: description, periods: activePeriods)
        self.type = type
        self.effect = effect
        self.severity = severity
        self.isPlanned = isPlanned
        self.activePeriods = activePeriods
        self.header = header
        self.description = description
    }

    /// An alert MOTIS attached to a departure or leg, with its `communicationPeriod` (the MTA's `active_period`) as
    /// its active periods, its `effectDetail` as the MTA's type, and that type's severity where MOTIS gives none.
    public init(_ alert: Components.Schemas.Alert) {
        let type = alert.effectDetail.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        self.init(
            type: type,
            effect: alert.effect?.rawValue,
            severity: alert.severityLevel?.rawValue ?? MTAAlertType.severity(of: type),
            isPlanned: alert.cause == .maintenance,
            activePeriods: (alert.communicationPeriod ?? []).map { AlertPeriod(start: $0.start, end: $0.end) },
            header: alert.headerText,
            description: alert.descriptionText
        )
    }

    /// How much it matters, from its effect and severity.
    public var level: AlertLevel {
        AlertLevel(effect: effect, severity: severity)
    }

    /// The header to show: the MTA's, or a generic notice where it wrote none.
    public var displayHeader: String {
        let trimmed = header.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Service notice" : trimmed
    }

    /// Whether the alert applies at `date`: inside one of its active periods, or always where it has none.
    public func isActive(at date: Date) -> Bool {
        activePeriods.isEmpty || activePeriods.contains { $0.contains(date) }
    }

    /// Whether the alert applies at any moment of `interval`, such as a ride from boarding to alighting.
    public func isActive(during interval: DateInterval) -> Bool {
        activePeriods.isEmpty || activePeriods.contains { $0.overlaps(interval) }
    }

    /// The next time it starts to apply after `date`, while it doesn't apply at `date`: when upcoming work begins.
    /// `nil` where it applies now or never will again.
    public func nextStart(after date: Date) -> Date? {
        guard !isActive(at: date) else { return nil }
        return activePeriods.compactMap(\.start).filter { $0 > date }.min()
    }

    /// The periods that haven't ended by `date`, soonest first: the dates to show for upcoming work.
    public func remainingPeriods(after date: Date) -> [AlertPeriod] {
        activePeriods
            .filter { $0.end.map { $0 > date } ?? true }
            .sorted { ($0.start ?? .distantPast) < ($1.start ?? .distantPast) }
    }

    private static func id(header: String, description: String?, periods: [AlertPeriod]) -> String {
        let times = periods.map { period in
            [period.start, period.end].map { $0.map { String(Int($0.timeIntervalSince1970)) } ?? "" }
                .joined(separator: "-")
        }
        return ([header, description ?? ""] + times).joined(separator: "|")
    }
}

public extension Sequence<ServiceAlert> {
    /// The alerts active at `date`, each once, the most severe first (feed order within a level).
    func active(at date: Date) -> [ServiceAlert] {
        uniqued().filter { $0.isActive(at: date) }.sortedBySeverity()
    }

    /// The alerts not active at `date` that will be later, soonest first: upcoming work.
    func upcoming(after date: Date) -> [ServiceAlert] {
        uniqued()
            .compactMap { alert in alert.nextStart(after: date).map { (alert, $0) } }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    /// Each alert once, by id, in order.
    internal func uniqued() -> [ServiceAlert] {
        var seen: Set<String> = []
        return filter { seen.insert($0.id).inserted }
    }

    /// The most severe first, keeping the order within a level.
    internal func sortedBySeverity() -> [ServiceAlert] {
        enumerated()
            .sorted {
                $0.element.level != $1.element.level ? $0.element.level > $1.element.level : $0.offset < $1.offset
            }
            .map(\.element)
    }
}

public extension Departure {
    /// Every alert MOTIS attached to this departure, whatever its time.
    var serviceAlerts: [ServiceAlert] {
        (place.alerts ?? []).map(ServiceAlert.init)
    }

    /// The alerts that apply to this departure: those active at the time it leaves (or, without one, at `now`).
    func currentAlerts(now: Date) -> [ServiceAlert] {
        serviceAlerts.active(at: time ?? now)
    }
}

public extension LineDepartures {
    /// The alerts that apply to the line in this direction: each departure's alerts active at the time it leaves,
    /// each once, the most severe first.
    func currentAlerts(now: Date) -> [ServiceAlert] {
        departures.flatMap { $0.currentAlerts(now: now) }.uniqued().sortedBySeverity()
    }

    /// The line's id for line status: the route id without its feed (`6X` for `us-ny-MTA-NYCSubway_6X`).
    var lineStatusId: String {
        LineStatusLine.lineId(routeId: routeId)
    }
}

public extension StopBoard {
    /// The alerts that apply to the departures on the board, across every line and direction, each once, the most
    /// severe first: what the stop screen shows under the stop's name.
    func currentAlerts() -> [ServiceAlert] {
        lines.flatMap { $0.currentAlerts(now: fetchedAt) }.uniqued().sortedBySeverity()
    }
}

/// A line near the rider with alerts that apply to it now, for the home sheet's summary ("2 lines with alerts").
public struct LineAlertSummary: Sendable, Hashable, Identifiable {
    /// The line as line status names it, express variants under their line (`6` for the 6X).
    public var id: String
    public var bullet: LineBullet
    /// Its current alerts in either direction, each once, the most severe first.
    public var alerts: [ServiceAlert]

    /// The most severe of its alerts.
    public var level: AlertLevel {
        alerts.map(\.level).max() ?? .info
    }
}

public extension NearbyBoard {
    /// The lines on the board with alerts that apply to their departures, the most severe first, then in the
    /// board's order. A line's directions and its express variant count as one line.
    func linesWithAlerts() -> [LineAlertSummary] {
        var summaries: [LineAlertSummary] = []
        for line in stops.flatMap(\.lines) {
            let alerts = line.currentAlerts(now: fetchedAt)
            guard !alerts.isEmpty else { continue }
            let id = LineStatusLine.parentLineId(line.lineStatusId)
            if let index = summaries.firstIndex(where: { $0.id == id }) {
                summaries[index].alerts = (summaries[index].alerts + alerts).uniqued().sortedBySeverity()
            } else {
                var bullet = line.bullet
                if bullet.shape == .diamond {
                    bullet.shape = .circle
                }
                summaries.append(LineAlertSummary(id: id, bullet: bullet, alerts: alerts))
            }
        }
        return summaries.enumerated()
            .sorted {
                $0.element.level != $1.element.level ? $0.element.level > $1.element.level : $0.offset < $1.offset
            }
            .map(\.element)
    }

    /// The bus routes on the board, each once, in the board's order, for line status.
    func busLines() -> [LineStatusLine] {
        var seen: Set<String> = []
        return stops.flatMap(\.lines).compactMap { line in
            guard line.mode == .bus, seen.insert(line.lineStatusId).inserted else { return nil }
            return LineStatusLine(id: line.lineStatusId, bullet: line.bullet, name: nil)
        }
    }
}
