import Foundation
import Testing
@testable import TransitKit

/// ``MTAAlertType``: the server's alert-type table as the app reads it, and the same level on every screen.
struct MTAAlertTypeTests {
    /// `apps/api/motis/adapter/alert_types.json`, the one table the adapter and line status map types with.
    struct Table: Decodable {
        var plannedPrefix: String
        var types: [String: AlertTypeEntry]
    }

    static func table() throws -> Table {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // TransitKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // transitkit
            .deletingLastPathComponent() // packages
            .deletingLastPathComponent() // the repository
            .appending(path: "apps/api/motis/adapter/alert_types.json")
        return try JSONDecoder().decode(Table.self, from: Data(contentsOf: url))
    }

    /// MOTIS passes no severity on departures and legs, only the MTA's type as `effectDetail`; the type's severity
    /// from ``MTAAlertType`` makes a minor modified service neutral, as on line status.
    @Test func departureAlertsTakeTheirTypesSeverity() {
        func level(_ effect: Components.Schemas.AlertEffect, _ type: String?) -> AlertLevel {
            ServiceAlert(Components.Schemas.Alert(
                cause: .unknownCause,
                effect: effect,
                effectDetail: type,
                headerText: "Alert",
                descriptionText: ""
            )).level
        }
        #expect(level(.modifiedService, "Planned - Express to Local") == .info)
        #expect(level(.modifiedService, "Express to Local") == .info)
        #expect(level(.stopMoved, "Boarding Change") == .info)
        #expect(level(.modifiedService, "Planned - Stops Skipped") == .severe)
        #expect(level(.noService, "Part Suspended") == .severe)
        #expect(level(.significantDelays, "Delays") == .warning)
        #expect(level(.detour, "Planned - Reroute") == .warning)
        // No type, or one the table doesn't know: the effect alone, so a modified service still reads as severe.
        #expect(level(.modifiedService, nil) == .severe)
        #expect(level(.modifiedService, " ") == .severe)
        #expect(level(.modifiedService, "Alien Invasion") == .severe)
        #expect(level(.significantDelays, nil) == .warning)

        let alert = ServiceAlert(Components.Schemas.Alert(
            cause: .maintenance,
            effect: .modifiedService,
            effectDetail: "Planned - Express to Local",
            headerText: "Alert",
            descriptionText: ""
        ))
        #expect(alert.type == "Planned - Express to Local")
        #expect(alert.severity == "INFO")
    }

    /// A severity MOTIS does pass wins over the type's.
    @Test func aSeverityMOTISPassesWins() {
        let alert = ServiceAlert(Components.Schemas.Alert(
            cause: .unknownCause,
            effect: .modifiedService,
            effectDetail: "Express to Local",
            headerText: "Alert",
            descriptionText: "",
            severityLevel: .warning
        ))
        #expect(alert.level == .severe)
    }

    @Test func mirrorsTheServersTable() throws {
        let table = try Self.table()
        #expect(MTAAlertType.plannedPrefix == table.plannedPrefix)
        #expect(MTAAlertType.severities == table.types.mapValues(\.severity), "Mirror alert_types.json")
        #expect(MTAAlertType.skippingStops.isSubset(of: Set(table.types.keys)))
    }

    /// Line status's level (the server's effect and severity) and a departure's (MOTIS's effect and the type it passes
    /// on) agree for every type, planned or not.
    @Test func departuresAndLineStatusAgreeOnEveryType() throws {
        let table = try Self.table()
        for (type, entry) in table.types {
            let lineStatus = AlertLevel(effect: entry.effect, severity: entry.severity)
            for name in [type, table.plannedPrefix + type] {
                let effect = try #require(Components.Schemas.AlertEffect(rawValue: entry.effect))
                let departure = ServiceAlert(Components.Schemas.Alert(
                    cause: .unknownCause,
                    effect: effect,
                    effectDetail: name,
                    headerText: name,
                    descriptionText: ""
                ))
                #expect(departure.level == lineStatus, "\(name)")
            }
        }
    }

    /// The mapping line status shows: suspensions and skipped stops red, delays and reroutes amber, and
    /// express-to-local, boarding changes, and other notices neutral.
    @Test func theMapping() throws {
        let table = try Self.table()
        func level(_ type: String) throws -> AlertLevel {
            let entry = try #require(table.types[type])
            return AlertLevel(effect: entry.effect, severity: MTAAlertType.severity(of: type))
        }
        for type in ["Suspended", "Part Suspended", "Stops Skipped"] {
            #expect(try level(type) == .severe, "\(type)")
        }
        for type in ["Delays", "Severe Delays", "Reroute", "Trains Rerouted", "Detour", "Reduced Service"] {
            #expect(try level(type) == .warning, "\(type)")
        }
        for type in ["Express to Local", "Boarding Change", "Extra Transfer", "Station Notice", "Special Notice"] {
            #expect(try level(type) == .info, "\(type)")
        }
    }

    @Test func plannedTypesAndUnknownOnes() {
        #expect(MTAAlertType.severity(of: "Planned - Part Suspended") == "SEVERE")
        #expect(MTAAlertType.severity(of: "Planned - Express to Local") == "INFO")
        #expect(MTAAlertType.severity(of: "Alien Invasion") == nil)
        #expect(MTAAlertType.severity(of: "Planned - Alien Invasion") == nil)
        #expect(MTAAlertType.severity(of: "") == nil)
        #expect(MTAAlertType.severity(of: nil) == nil)
    }

    @Test func whichTypesSkipStops() {
        #expect(MTAAlertType.skipsStops("Planned - Stops Skipped") == true)
        #expect(MTAAlertType.skipsStops("Suspended") == true)
        #expect(MTAAlertType.skipsStops("Planned - Part Suspended") == true)
        #expect(MTAAlertType.skipsStops("Express to Local") == false)
        #expect(MTAAlertType.skipsStops("Local to Express") == false)
        #expect(MTAAlertType.skipsStops("Boarding Change") == false)
        #expect(MTAAlertType.skipsStops("Alien Invasion") == nil)
        #expect(MTAAlertType.skipsStops(nil) == nil)
    }
}

/// One type's row in `alert_types.json`.
struct AlertTypeEntry: Decodable {
    var effect: String
    var severity: String
}
