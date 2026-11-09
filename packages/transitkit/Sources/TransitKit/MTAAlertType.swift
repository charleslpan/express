import Foundation

/// The MTA's own alert types (the `mercury_alert` extension's `alert_type`, such as "Planned - Express to Local") and
/// the GTFS-RT severity level our server gives each.
///
/// Line status gets the severity from the server. MOTIS drops `severity_level` from departures and legs, so our
/// adapter writes the type into `effect_detail`, which MOTIS passes on, and the app looks its severity up here.
/// ``severities`` is a checked copy of `apps/api/motis/adapter/alert_types.json`'s severities (a test fails when the
/// two differ): edit the JSON, then mirror it here.
public enum MTAAlertType {
    /// The prefix of planned work's types ("Planned - Part Suspended"), looked up whole and then without it.
    public static let plannedPrefix = "Planned - "

    /// Each type's severity level, as `alert_types.json` gives it.
    static let severities: [String: String] = [
        "Suspended": "SEVERE",
        "Part Suspended": "SEVERE",
        "No Scheduled Service": "INFO",
        "Severe Delays": "SEVERE",
        "Delays": "WARNING",
        "Some Delays": "WARNING",
        "Expect Delays": "INFO",
        "Slow Speeds": "WARNING",
        "Reduced Service": "WARNING",
        "Cancellations": "WARNING",
        "Stops Skipped": "WARNING",
        "Local to Express": "WARNING",
        "Express to Local": "INFO",
        "Extra Transfer": "INFO",
        "Multiple Changes": "WARNING",
        "Special Schedule": "INFO",
        "Weekday Service": "INFO",
        "Weekend Service": "INFO",
        "Reroute": "WARNING",
        "Trains Rerouted": "WARNING",
        "Detour": "WARNING",
        "Extra Service": "INFO",
        "Boarding Change": "INFO",
        "Station Notice": "INFO",
        "Special Notice": "INFO",
    ]

    /// The types that say trains (or buses) don't stop somewhere: skipped stops and suspensions.
    static let skippingStops: Set<String> = ["Stops Skipped", "Suspended", "Part Suspended"]

    /// The type as the table knows it ("Part Suspended" for "Planned - Part Suspended"); `nil` for a type it doesn't.
    static func known(_ type: String?) -> String? {
        guard let type = type?.trimmingCharacters(in: .whitespacesAndNewlines), !type.isEmpty else { return nil }
        if severities[type] != nil {
            return type
        }
        guard type.hasPrefix(plannedPrefix) else { return nil }
        let base = String(type.dropFirst(plannedPrefix.count))
        return severities[base] != nil ? base : nil
    }

    /// The severity level the table gives `type`, such as `INFO` for "Planned - Express to Local"; `nil` for a type it
    /// doesn't know, or none, which leaves an alert to its effect alone.
    public static func severity(of type: String?) -> String? {
        known(type).flatMap { severities[$0] }
    }

    /// Whether `type` says trains skip a stop or don't run there ("Stops Skipped", "Suspended", "Part Suspended",
    /// planned or not); `nil` for a type the table doesn't know, or none.
    public static func skipsStops(_ type: String?) -> Bool? {
        known(type).map { skippingStops.contains($0) }
    }
}
