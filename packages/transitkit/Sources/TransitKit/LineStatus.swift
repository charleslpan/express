import Foundation
import HTTPTypes
import OpenAPIRuntime
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// A line on the line status screen: a subway line from ``LineStatusLine/subway``, or a bus route near the rider.
public struct LineStatusLine: Sendable, Hashable, Identifiable {
    /// The line's GTFS `route_id` without its feed, as the line status endpoint takes it (`A`, `GS`, `M15+`).
    public var id: String
    public var bullet: LineBullet
    /// The line's name where the bullet doesn't say it, such as "42 St Shuttle" for an `S`.
    public var name: String?
    /// Other route ids whose alerts count as this line's: an express variant's (`6X` for the 6).
    public var variantIds: [String]

    public init(id: String, bullet: LineBullet, name: String?, variantIds: [String] = []) {
        self.id = id
        self.bullet = bullet
        self.name = name
        self.variantIds = variantIds
    }

    /// Every id to ask the endpoint for: the line's and its variants'.
    public var requestIds: [String] {
        [id] + variantIds
    }

    /// The route id without its feed (`us-ny-MTA-NYCSubway_6X` is `6X`, `us-ny-MTA-BusManhattan_M14A+` is `M14A+`).
    public static func lineId(routeId: String) -> String {
        routeId.split(separator: "_", maxSplits: 1).last.map(String.init) ?? routeId
    }

    /// The line an express variant belongs to (`6` for `6X`); other ids as they are.
    public static func parentLineId(_ id: String) -> String {
        LineBullet.isExpressVariant(id) ? String(id.dropLast()) : id
    }

    /// Every subway line riders know, in the MTA's order, with the feed's own colours (the MTA's supplemented
    /// subway GTFS `routes.txt`, Nov 2026). Express variants (6X, 7X, FX) count as their line; the three shuttles
    /// are each an `S`, named; the Staten Island Railway is SIR.
    public static let subway: [LineStatusLine] = {
        let red = RGBColor(hex: "D82233"), green = RGBColor(hex: "009952"), purple = RGBColor(hex: "9A38A1")
        let blue = RGBColor(hex: "0062CF"), orange = RGBColor(hex: "EB6800"), lime = RGBColor(hex: "799534")
        let brown = RGBColor(hex: "8E5C33"), grey = RGBColor(hex: "7C858C"), yellow = RGBColor(hex: "F6BC26")
        let navy = RGBColor(hex: "08179C"), white = RGBColor(hex: "FFFFFF"), black = RGBColor(hex: "000000")
        func line(_ id: String, _ color: RGBColor?, text: RGBColor? = white, name: String? = nil) -> LineStatusLine {
            let bulletText = name == nil ? id : "S"
            return LineStatusLine(
                id: id,
                bullet: LineBullet(text: bulletText, shape: .circle, color: color, textColor: text),
                name: name,
                variantIds: ["6", "7", "F"].contains(id) ? ["\(id)X"] : []
            )
        }
        return [
            line("1", red), line("2", red), line("3", red),
            line("4", green), line("5", green), line("6", green),
            line("7", purple),
            line("A", blue), line("C", blue), line("E", blue),
            line("B", orange), line("D", orange), line("F", orange), line("M", orange),
            line("G", lime),
            line("J", brown), line("Z", brown),
            line("L", grey),
            line("N", yellow, text: black), line("Q", yellow, text: black), line("R", yellow, text: black),
            line("W", yellow, text: black),
            line("GS", grey, name: "42 St Shuttle"),
            line("FS", grey, name: "Franklin Av Shuttle"),
            line("H", grey, name: "Rockaway Park Shuttle"),
            LineStatusLine(
                id: "SI",
                bullet: LineBullet(text: "SIR", shape: .label, color: navy, textColor: white),
                name: "Staten Island Railway"
            ),
        ]
    }()
}

/// What the line status endpoint (`GET /api/alerts?lines=…`) answers: every requested line's alerts, future ones
/// included, as the MTA's feeds hold them.
public struct LineStatusResponse: Sendable, Hashable {
    /// Each requested line's alerts, by its id; empty where it has none.
    public var lines: [String: [ServiceAlert]]
    /// When the MTA's subway and bus alert feeds were produced, where known.
    public var subwayUpdatedAt: Date?
    public var busUpdatedAt: Date?

    public init(lines: [String: [ServiceAlert]], subwayUpdatedAt: Date? = nil, busUpdatedAt: Date? = nil) {
        self.lines = lines
        self.subwayUpdatedAt = subwayUpdatedAt
        self.busUpdatedAt = busUpdatedAt
    }

    /// A line's alerts with its variants', each once, in feed order.
    public func alerts(for line: LineStatusLine) -> [ServiceAlert] {
        line.requestIds.flatMap { lines[$0] ?? [] }.uniqued()
    }

    /// Decodes the endpoint's JSON (see `apps/api/README.md`, "Line status").
    public init(json data: Data) throws(TransitError) {
        let wire: LineStatusWire
        do {
            wire = try JSONDecoder().decode(LineStatusWire.self, from: data)
        } catch {
            throw .decoding(String(describing: error))
        }
        lines = wire.lines.mapValues { $0.map(\.alert) }
        subwayUpdatedAt = wire.updatedAt?.subway.map { Date(timeIntervalSince1970: $0) }
        busUpdatedAt = wire.updatedAt?.bus.map { Date(timeIntervalSince1970: $0) }
    }
}

/// The line status endpoint's JSON. Effects and severities stay strings, so a value this app doesn't know reads as a
/// neutral notice rather than failing the whole answer.
private struct LineStatusWire: Decodable {
    struct UpdatedAt: Decodable {
        var subway: Double?
        var bus: Double?
    }

    var updatedAt: UpdatedAt?
    var lines: [String: [LineStatusWireAlert]]
}

private struct LineStatusWirePeriod: Decodable {
    var start: Double?
    var end: Double?
}

private struct LineStatusWireAlert: Decodable {
    var id: String
    var type: String?
    var effect: String?
    var cause: String?
    var severity: String?
    var activePeriods: [LineStatusWirePeriod]?
    var header: String?
    var description: String?

    var alert: ServiceAlert {
        ServiceAlert(
            id: id,
            type: type,
            effect: effect,
            severity: severity,
            isPlanned: cause == "MAINTENANCE" || type?.hasPrefix("Planned") == true,
            activePeriods: (activePeriods ?? []).map {
                AlertPeriod(
                    start: $0.start.map { Date(timeIntervalSince1970: $0) },
                    end: $0.end.map { Date(timeIntervalSince1970: $0) }
                )
            },
            header: header ?? "",
            description: description
        )
    }
}

public extension TransitClient {
    /// The most lines the endpoint takes in one request.
    static let lineStatusBatchSize = 50

    /// Every alert on `lines` (GTFS `route_id`s without their feed, such as `A`, `6X`, `M15+`), future ones included,
    /// from our server's line status endpoint (`GET /api/alerts`). Asks in batches of
    /// ``lineStatusBatchSize``, together. Show an alert only while it applies
    /// (``ServiceAlert/isActive(at:)``); planned work not yet active is upcoming (``Swift/Sequence/upcoming(after:)``).
    func lineStatus(lines: [String]) async throws(TransitError) -> LineStatusResponse {
        var unique: [String] = []
        for line in lines where !unique.contains(line) {
            unique.append(line)
        }
        guard !unique.isEmpty else { return LineStatusResponse(lines: [:]) }
        let batches = stride(from: 0, to: unique.count, by: Self.lineStatusBatchSize).map {
            Array(unique[$0 ..< min($0 + Self.lineStatusBatchSize, unique.count)])
        }
        do {
            return try await withThrowingTaskGroup(of: LineStatusResponse.self) { group in
                for batch in batches {
                    group.addTask { try await self.lineStatusBatch(batch) }
                }
                var merged = LineStatusResponse(lines: [:])
                for try await response in group {
                    merged.lines.merge(response.lines) { first, _ in first }
                    merged.subwayUpdatedAt = merged.subwayUpdatedAt ?? response.subwayUpdatedAt
                    merged.busUpdatedAt = merged.busUpdatedAt ?? response.busUpdatedAt
                }
                return merged
            }
        } catch {
            throw TransitError(error)
        }
    }

    private func lineStatusBatch(_ lines: [String]) async throws(TransitError) -> LineStatusResponse {
        // `+` (Select Bus Service) is sent as %2B, which the endpoint reads as itself.
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-")
        let list = lines.map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0 }.joined(separator: ",")
        let request = HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/api/alerts?lines=\(list)")
        do {
            let (response, body) = try await userAgent.intercept(
                request,
                body: nil,
                baseURL: baseURL,
                operationID: "lineStatus",
                next: { [transport] request, body, baseURL in
                    try await transport.send(request, body: body, baseURL: baseURL, operationID: "lineStatus")
                }
            )
            guard response.status == .ok else {
                throw TransitError(
                    undocumentedStatus: response.status.code,
                    payload: UndocumentedPayload(headerFields: response.headerFields, body: body)
                )
            }
            guard let body else { throw TransitError.decoding("The line status answer had no body") }
            return try await LineStatusResponse(json: Data(collecting: body, upTo: 8 * 1024 * 1024))
        } catch {
            throw TransitError(error)
        }
    }
}
