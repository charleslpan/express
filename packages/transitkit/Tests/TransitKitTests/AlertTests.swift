import Foundation
import HTTPTypes
import Testing
@testable import TransitKit

/// The time-window rule: an alert applies only inside one of its active periods.
struct AlertTimeWindowTests {
    /// Noon on Tuesday, Nov 3, 2026 in New York.
    static let noon = Date(timeIntervalSince1970: 1_793_725_200)

    static func alert(
        _ periods: [AlertPeriod],
        effect: String? = "NO_SERVICE",
        header: String = "Alert"
    ) -> ServiceAlert {
        ServiceAlert(effect: effect, isPlanned: true, activePeriods: periods, header: header, description: nil)
    }

    static func at(_ hours: Double) -> Date {
        noon.addingTimeInterval(hours * 3600)
    }

    @Test func appliesInsideItsPeriod() {
        let alert = Self.alert([AlertPeriod(start: Self.at(-1), end: Self.at(1))])
        #expect(alert.isActive(at: Self.noon))
    }

    @Test func doesNotApplyOutsideItsPeriod() {
        let alert = Self.alert([AlertPeriod(start: Self.at(-1), end: Self.at(1))])
        #expect(!alert.isActive(at: Self.at(-2)))
        #expect(!alert.isActive(at: Self.at(2)))
    }

    /// The live-data case the filter exists for: a night-work suspension two weeks away never shows on a noon train.
    @Test func futureNightWorkNeverAppliesToANoonTrain() {
        let nights = (14 ... 16).map { day in
            AlertPeriod(start: Self.at(Double(day) * 24 + 11.75), end: Self.at(Double(day) * 24 + 17))
        }
        let alert = Self.alert(nights)
        #expect(!alert.isActive(at: Self.noon))
        #expect([alert].active(at: Self.noon).isEmpty)
        #expect([alert].upcoming(after: Self.noon) == [alert])
        #expect(alert.nextStart(after: Self.noon) == nights[0].start)
    }

    @Test func openEndedPeriods() {
        let untilFurtherNotice = Self.alert([AlertPeriod(start: Self.at(-24 * 30), end: nil)])
        #expect(untilFurtherNotice.isActive(at: Self.noon))
        #expect(untilFurtherNotice.isActive(at: Self.at(24 * 365)))
        #expect(!untilFurtherNotice.isActive(at: Self.at(-24 * 31)))

        let sinceForever = Self.alert([AlertPeriod(start: nil, end: Self.at(1))])
        #expect(sinceForever.isActive(at: Self.at(-24 * 365)))
        #expect(!sinceForever.isActive(at: Self.at(1)))
    }

    @Test func noPeriodsMeansAlwaysActive() {
        #expect(Self.alert([]).isActive(at: Self.noon))
        #expect(Self.alert([]).nextStart(after: Self.noon) == nil)
    }

    @Test func multiplePeriods() {
        // Two weekend nights: 11:45 PM to 5 AM.
        let alert = Self.alert([
            AlertPeriod(start: Self.at(11.75), end: Self.at(17)),
            AlertPeriod(start: Self.at(35.75), end: Self.at(41)),
        ])
        #expect(!alert.isActive(at: Self.noon))
        #expect(alert.isActive(at: Self.at(12)))
        #expect(!alert.isActive(at: Self.at(24)), "between the nights")
        #expect(alert.isActive(at: Self.at(36)))
        #expect(!alert.isActive(at: Self.at(42)))
        #expect(alert.nextStart(after: Self.noon) == Self.at(11.75))
        #expect(alert.nextStart(after: Self.at(24)) == Self.at(35.75))
        #expect(alert.remainingPeriods(after: Self.at(24)).map(\.start) == [Self.at(35.75)])
    }

    /// The period includes its start and excludes its end, so a departure on either side of a boundary lands right.
    @Test func departureCrossingABoundary() {
        let start = Self.at(11.75)
        let end = Self.at(17)
        let alert = Self.alert([AlertPeriod(start: start, end: end)])
        #expect(!alert.isActive(at: start.addingTimeInterval(-1)))
        #expect(alert.isActive(at: start))
        #expect(alert.isActive(at: end.addingTimeInterval(-1)))
        #expect(!alert.isActive(at: end))

        // A ride boarding before the work starts and still riding when it does is affected; one that ends as it
        // starts, or boards as it ends, isn't.
        #expect(alert.isActive(during: DateInterval(
            start: start.addingTimeInterval(-600),
            end: start.addingTimeInterval(60)
        )))
        #expect(!alert.isActive(during: DateInterval(start: start.addingTimeInterval(-600), end: start)))
        #expect(alert.isActive(during: DateInterval(
            start: end.addingTimeInterval(-60),
            end: end.addingTimeInterval(600)
        )))
        #expect(!alert.isActive(during: DateInterval(start: end, end: end.addingTimeInterval(600))))
    }

    @Test func departureAlertsUseTheDepartureTimeNotNow() throws {
        let departures = try DepartureGroupingTests.unionSquare()
        var departure = try #require(departures.first)
        let leaves = try #require(departure.time)
        departure.place.alerts = [
            Components.Schemas.Alert(
                communicationPeriod: [.init(start: leaves.addingTimeInterval(-60), end: leaves.addingTimeInterval(60))],
                cause: .unknownCause,
                effect: .significantDelays,
                headerText: "[L] trains are running with delays",
                descriptionText: ""
            ),
            Components.Schemas.Alert(
                communicationPeriod: [.init(
                    start: leaves.addingTimeInterval(14 * 86400),
                    end: leaves.addingTimeInterval(15 * 86400)
                )],
                cause: .maintenance,
                effect: .noService,
                headerText: "No [L] trains between 8 Av and Broadway Junction",
                descriptionText: "Take the [M] instead."
            ),
        ]
        // "Now" is ten minutes before the train leaves and before the delays began; the train's time decides.
        let now = leaves.addingTimeInterval(-600)
        let current = departure.currentAlerts(now: now)
        #expect(current.map(\.header) == ["[L] trains are running with delays"])
        #expect(current.first?.level == .warning)
        #expect(current.first?.description == nil, "an empty description reads as none")
        #expect(departure.serviceAlerts.count == 2)
        #expect(departure.serviceAlerts[1].isPlanned)
    }
}

struct AlertLevelTests {
    @Test func levelsFromEffect() {
        #expect(AlertLevel(effect: "NO_SERVICE") == .severe)
        #expect(AlertLevel(effect: "MODIFIED_SERVICE", severity: "WARNING") == .severe, "Stops Skipped")
        #expect(AlertLevel(effect: "MODIFIED_SERVICE") == .severe, "MOTIS passes no severity")
        #expect(AlertLevel(effect: "MODIFIED_SERVICE", severity: "INFO") == .info, "Express to Local")
        #expect(AlertLevel(effect: "SIGNIFICANT_DELAYS") == .warning)
        #expect(AlertLevel(effect: "DETOUR") == .warning)
        #expect(AlertLevel(effect: "REDUCED_SERVICE") == .warning)
        #expect(AlertLevel(effect: "STOP_MOVED") == .info)
        #expect(AlertLevel(effect: "OTHER_EFFECT") == .info)
        #expect(AlertLevel(effect: "SOMETHING_NEW") == .info, "unknown effects are neutral notices")
        #expect(AlertLevel(effect: nil) == .info)
    }

    @Test func mostSevereFirst() {
        let notice = AlertTimeWindowTests.alert([], effect: "OTHER_EFFECT", header: "Notice")
        let delays = AlertTimeWindowTests.alert([], effect: "SIGNIFICANT_DELAYS", header: "Delays")
        let suspended = AlertTimeWindowTests.alert([], effect: "NO_SERVICE", header: "Suspended")
        let sorted = [notice, delays, suspended, delays].active(at: AlertTimeWindowTests.noon)
        #expect(sorted.map(\.header) == ["Suspended", "Delays", "Notice"])
    }

    @Test func emptyHeaderReadsAsAGenericNotice() {
        let alert = AlertTimeWindowTests.alert([], effect: nil, header: "  ")
        #expect(alert.displayHeader == "Service notice")
        #expect(alert.level == .info)
    }
}

struct LineStatusTests {
    static let json = Data("""
    {
      "updatedAt": { "subway": 1793741003, "bus": null },
      "lines": {
        "2": [
          {
            "id": "lmm:alert:274734:26",
            "type": "Delays",
            "effect": "SIGNIFICANT_DELAYS",
            "cause": "UNKNOWN_CAUSE",
            "severity": "WARNING",
            "activePeriods": [{ "start": 1793740456, "end": 1793742540 }],
            "header": "Wakefield-241 St-bound [2] and Eastchester-Dyre Av-bound [5] trains are running with delays.",
            "description": null,
            "affected": [{ "stopId": null, "directionId": null }]
          },
          {
            "id": "lmm:planned_work:1",
            "type": "Planned - Part Suspended",
            "effect": "NO_SERVICE",
            "cause": "MAINTENANCE",
            "severity": "SEVERE",
            "activePeriods": [{ "start": 1795000000, "end": null }],
            "header": "No [2] trains between 149 St-Grand Concourse and 241 St",
            "description": "Take the [5] instead.",
            "affected": []
          },
          {
            "id": "lmm:alert:9",
            "type": "Alien Invasion",
            "effect": "BRAND_NEW_EFFECT",
            "cause": "UNKNOWN_CAUSE",
            "severity": "INFO",
            "activePeriods": [],
            "header": "",
            "description": null,
            "affected": []
          }
        ],
        "6": [],
        "6X": [{
          "id": "lmm:alert:6x", "type": "Reroute", "effect": "DETOUR", "cause": "UNKNOWN_CAUSE", "severity": "WARNING",
          "activePeriods": [], "header": "[6] express trains run local", "description": null, "affected": []
        }]
      }
    }
    """.utf8)

    @Test func decodesTheEndpointsAnswer() throws {
        let response = try LineStatusResponse(json: Self.json)
        #expect(response.subwayUpdatedAt == Date(timeIntervalSince1970: 1_793_741_003))
        #expect(response.busUpdatedAt == nil)
        let two = try #require(response.lines["2"])
        #expect(two.map(\.id) == ["lmm:alert:274734:26", "lmm:planned_work:1", "lmm:alert:9"])
        #expect(two[0].level == .warning)
        #expect(!two[0].isPlanned)
        #expect(two[1].isPlanned)
        #expect(two[1].level == .severe)
        #expect(two[1].activePeriods == [AlertPeriod(start: Date(timeIntervalSince1970: 1_795_000_000), end: nil)])
        #expect(two[2].level == .info, "an unknown effect falls back to a neutral notice")
        #expect(two[2].displayHeader == "Service notice")
    }

    @Test func splitsCurrentFromUpcoming() throws {
        let response = try LineStatusResponse(json: Self.json)
        let now = Date(timeIntervalSince1970: 1_793_741_000)
        let alerts = try #require(response.lines["2"])
        #expect(alerts.active(at: now).map(\.id) == ["lmm:alert:274734:26", "lmm:alert:9"])
        #expect(alerts.upcoming(after: now).map(\.id) == ["lmm:planned_work:1"])
        // Once the delays end, only the notice is current.
        #expect(alerts.active(at: Date(timeIntervalSince1970: 1_793_742_540)).map(\.id) == ["lmm:alert:9"])
    }

    @Test func expressVariantsCountAsTheirLine() throws {
        let response = try LineStatusResponse(json: Self.json)
        let six = try #require(LineStatusLine.subway.first { $0.id == "6" })
        #expect(six.requestIds == ["6", "6X"])
        #expect(response.alerts(for: six).map(\.id) == ["lmm:alert:6x"])
        #expect(LineStatusLine.parentLineId("7X") == "7")
        #expect(LineStatusLine.lineId(routeId: "us-ny-MTA-BusManhattan_M14A+") == "M14A+")
    }

    @Test func listsEverySubwayLineOnce() {
        let ids = LineStatusLine.subway.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids.count == 26)
        #expect(LineStatusLine.subway.allSatisfy { $0.bullet.color != nil })
        #expect(LineStatusLine.subway.first { $0.id == "N" }?.bullet.textColor == RGBColor(hex: "000000"))
    }

    @Test func clientAsksTheEndpointWithEncodedLines() async throws {
        let transport = FixtureTransport(body: Self.json)
        let client = TransitClient(baseURL: TransitKit.defaultBaseURL, transport: transport)
        let response = try await client.lineStatus(lines: ["2", "6", "6X", "M15+", "2"])
        #expect(response.lines["2"]?.count == 3)
        #expect(transport.requests.map(\.path) == ["/api/alerts?lines=2,6,6X,M15%2B"])
    }

    @Test func clientAsksInBatches() async throws {
        let transport = FixtureTransport(body: Data(#"{"updatedAt":{"subway":null,"bus":null},"lines":{}}"#.utf8))
        let client = TransitClient(baseURL: TransitKit.defaultBaseURL, transport: transport)
        _ = try await client.lineStatus(lines: (1 ... 60).map(String.init))
        #expect(transport.requests.count == 2)
    }

    @Test func clientMapsFailures() async throws {
        let offline = TransitClient(transport: FixtureTransport(error: URLError(.notConnectedToInternet)))
        await #expect(throws: TransitError.offline) {
            try await offline.lineStatus(lines: ["A"])
        }
        let down = TransitClient(transport: FixtureTransport(status: .badGateway, body: Data(#"{"error":"x"}"#.utf8)))
        await #expect(throws: TransitError.server(statusCode: 502, message: nil)) {
            try await down.lineStatus(lines: ["A"])
        }
        let garbled = TransitClient(transport: FixtureTransport(body: Data("not json".utf8)))
        await #expect {
            try await garbled.lineStatus(lines: ["A"])
        } throws: { error in
            if case .decoding = error as? TransitError {
                true
            } else {
                false
            }
        }
    }
}

struct NearbyAlertTests {
    static let now = DepartureGroupingTests.now

    static func alert(
        _ effect: Components.Schemas.AlertEffect,
        _ header: String,
        from start: TimeInterval,
        to end: TimeInterval
    ) -> Components.Schemas.Alert {
        Components.Schemas.Alert(
            communicationPeriod: [.init(start: now.addingTimeInterval(start), end: now.addingTimeInterval(end))],
            cause: start > 0 ? .maintenance : .unknownCause,
            effect: effect,
            headerText: header,
            descriptionText: ""
        )
    }

    /// Union Square's board with the 6 (and 6X) suspended and the L delayed now, and the R's work two weeks away.
    static func board() throws -> NearbyBoard {
        var departures = try DepartureGroupingTests.unionSquare()
        let suspension = alert(
            .noService,
            "No [6] trains between 3 Av-138 St and Pelham Bay Park",
            from: -3600,
            to: 3600
        )
        let delays = alert(.significantDelays, "[L] trains are running with delays", from: -3600, to: 3600)
        let future = alert(.noService, "No [R] trains", from: 14 * 86400, to: 15 * 86400)
        for index in departures.indices {
            switch departures[index].routeShortName {
            case "6", "6X": departures[index].place.alerts = [suspension]
            case "L": departures[index].place.alerts = [delays]
            case "R": departures[index].place.alerts = [future]
            default: break
            }
        }
        let stop = NearbyStop(
            id: "us-ny-MTA-NYCSubway_635",
            name: "14 St-Union Sq",
            modes: [.subway],
            coordinate: Coordinate(latitude: 40.7347, longitude: -73.99),
            distance: 50
        )
        return NearbyBoard(
            stops: [stop],
            departures: [stop.id: departures],
            fetchedAt: now,
            dataAge: RealtimeDataAge(feedTimestamp: now)
        )
    }

    @Test func summarisesLinesWithCurrentAlertsMostSevereFirst() throws {
        let summary = try Self.board().linesWithAlerts()
        #expect(
            summary.map(\.id) == ["6", "L"],
            "the 6X counts as the 6, both directions as one, and the R's future work not at all"
        )
        #expect(summary.map(\.level) == [.severe, .warning])
        #expect(summary[0].alerts.count == 1)
        #expect(summary[0].bullet.shape == .circle)
    }

    @Test func rowsShowOnlyAlertsThatApplyToThem() throws {
        let rows = try Self.board().stops[0].lines
        let broadwayLocal = try #require(rows.first { $0.routeId.hasSuffix("_R") })
        #expect(broadwayLocal.currentAlerts(now: Self.now).isEmpty)
        let six = try #require(rows.first { $0.routeId.hasSuffix("_6") })
        #expect(six.currentAlerts(now: Self.now).map(\.level) == [.severe])
    }

    @Test func stopBoardListsEachCurrentAlertOnceMostSevereFirst() throws {
        let board = try Self.board()
        let departures = board.stops[0].lines.flatMap(\.departures)
        let stopBoard = StopBoard(stopTimes: departures, fetchedAt: Self.now, dataAge: board.dataAge)
        #expect(stopBoard.currentAlerts().map(\.header) == [
            "No [6] trains between 3 Av-138 St and Pelham Bay Park",
            "[L] trains are running with delays",
        ])
    }
}
