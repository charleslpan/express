import Foundation
import HTTPTypes
import OpenAPIRuntime
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// One MTA bus at its GPS position, as our server's `GET /api/vehicles/bus` returns it from MTA Bus Time.
public struct Bus: Sendable, Hashable, Identifiable, MapLocated, Decodable {
    /// Bus Time's vehicle id, such as `MTA NYCT_7582`.
    public var id: String
    /// The GTFS `route_id`, such as `M15`, or `M15+` for its Select Bus Service; `nil` where the feed gives none.
    public var route: String?
    /// The GTFS `direction_id`, 0 or 1.
    public var directionId: Int?
    /// The GTFS `trip_id` from the bus timetables MOTIS loads. Buses are often interlined, so it may belong to another
    /// route than ``route``.
    public var tripId: String?
    public var coordinate: Coordinate
    /// The direction of travel, in degrees clockwise from true north; `nil` where the feed gives none.
    public var bearing: Double?
    /// When the GPS fix was taken.
    public var timestamp: Date?

    public init(
        id: String,
        route: String?,
        directionId: Int? = nil,
        tripId: String? = nil,
        coordinate: Coordinate,
        bearing: Double? = nil,
        timestamp: Date? = nil
    ) {
        self.id = id
        self.route = route
        self.directionId = directionId
        self.tripId = tripId
        self.coordinate = coordinate
        self.bearing = bearing
        self.timestamp = timestamp
    }

    private enum CodingKeys: String, CodingKey {
        case id, route, directionId, tripId, lat, lon, bearing, timestamp
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        route = try container.decodeIfPresent(String.self, forKey: .route)
        directionId = try container.decodeIfPresent(Int.self, forKey: .directionId)
        tripId = try container.decodeIfPresent(String.self, forKey: .tripId)
        coordinate = try Coordinate(
            latitude: container.decode(Double.self, forKey: .lat),
            longitude: container.decode(Double.self, forKey: .lon)
        )
        bearing = try container.decodeIfPresent(Double.self, forKey: .bearing)
        timestamp = try container.decodeIfPresent(Double.self, forKey: .timestamp)
            .map(Date.init(timeIntervalSince1970:))
    }

    /// The way the bus is heading, in degrees clockwise from north (0 up to 360).
    ///
    /// The feed's bearing where it gives one. Otherwise the way the bus moved since `previous` (the same bus's last
    /// position), if it moved far enough for GPS noise not to matter, else the heading it had then, if any.
    ///
    /// - Parameters:
    ///   - previous: The bus as the last fetch had it.
    ///   - previousHeading: The heading it was shown with then.
    public func heading(after previous: Bus? = nil, previousHeading: Double? = nil) -> Double? {
        if let bearing, bearing.isFinite {
            return (bearing.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        }
        if let previous, previous.coordinate.distance(to: coordinate) >= Self.minimumMove {
            return previous.coordinate.bearing(to: coordinate)
        }
        return previousHeading
    }

    /// How far a bus must move, in metres, before the way it moved counts as its heading.
    static let minimumMove: Double = 15

    /// The bus's bullet: a label with its route's name ("M15-SBS"), in the route's colours from the feed where
    /// `style` gives them.
    public func lineBullet(style: BusRouteStyle?) -> LineBullet {
        let color = style?.color
        return LineBullet(
            text: style?.name ?? route.map(BusRouteStyle.name(forRouteID:)) ?? "Bus",
            shape: .label,
            color: color,
            textColor: style?.textColor ?? color.map(\.readableTextColor)
        )
    }
}

/// The buses in an area, and when Bus Time produced them.
public struct BusPositions: Sendable, Hashable, Decodable {
    /// When MTA Bus Time produced the feed; `nil` where it doesn't say.
    public var updatedAt: Date?
    public var vehicles: [Bus]

    public init(updatedAt: Date?, vehicles: [Bus]) {
        self.updatedAt = updatedAt
        self.vehicles = vehicles
    }

    private enum CodingKeys: String, CodingKey {
        case updatedAt, vehicles
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        updatedAt = try container.decodeIfPresent(Double.self, forKey: .updatedAt)
            .map(Date.init(timeIntervalSince1970:))
        vehicles = try container.decode([Bus].self, forKey: .vehicles)
    }

    /// How old the feed is, for saying when positions may not be real time.
    public var dataAge: RealtimeDataAge {
        RealtimeDataAge(feedTimestamp: updatedAt)
    }
}

/// How a bus route is labelled and coloured, from the MTA bus timetables MOTIS loads.
public struct BusRouteStyle: Sendable, Hashable {
    /// The route's short name, such as `M15-SBS`.
    public var name: String
    public var color: RGBColor?
    public var textColor: RGBColor?

    public init(name: String, color: RGBColor? = nil, textColor: RGBColor? = nil) {
        self.name = name
        self.color = color
        self.textColor = textColor
    }

    /// The name riders know a route by, from its GTFS `route_id` alone: Select Bus Service's `+` reads `-SBS`
    /// (`M15+` is `M15-SBS`); other ids are the name already (`M15`, `BxM1`).
    public static func name(forRouteID id: String) -> String {
        id.hasSuffix("+") ? "\(id.dropLast())-SBS" : id
    }

    /// The prefix of the MTA bus feeds' dataset tags on our server (`us-ny-MTA-BusManhattan`, `us-ny-MTA-BusCompany`).
    static let datasetPrefix = "us-ny-MTA-Bus"

    /// The MTA bus routes among `routes`, by their GTFS `route_id` (`M15+`, without MOTIS's dataset prefix).
    public static func styles(from routes: some Sequence<RouteInfo>) -> [String: BusRouteStyle] {
        var styles: [String: BusRouteStyle] = [:]
        for route in routes where route.mode == .bus {
            for transit in route.transitRoutes where transit.id.hasPrefix(datasetPrefix) {
                guard let separator = transit.id.firstIndex(of: "_") else { continue }
                let id = String(transit.id[transit.id.index(after: separator)...])
                styles[id] = BusRouteStyle(
                    name: transit.shortName.isEmpty ? name(forRouteID: id) : transit.shortName,
                    color: transit.color.flatMap(RGBColor.init(hex:)),
                    textColor: transit.textColor.flatMap(RGBColor.init(hex:))
                )
            }
        }
        return styles
    }
}

/// A route MOTIS lists in a map area, with its feed routes and their colours.
public typealias RouteInfo = Components.Schemas.RouteInfo

public extension CoordinateBounds {
    /// The bounds grown outward to the nearest lines of a grid `step` degrees apart, so nearby views of the map ask
    /// for the same area, and the CDN answers the repeats from its cache.
    func snapped(toGrid step: Double) -> CoordinateBounds {
        func snap(_ value: Double, _ rule: FloatingPointRoundingRule) -> Double {
            // Cells rounded to a millionth first, so an edge already on the grid stays put despite float noise; then
            // back to degrees, rounded to a micro-degree so the edges print cleanly.
            let cells = ((value / step) * 1_000_000).rounded() / 1_000_000
            return (cells.rounded(rule) * step * 1_000_000).rounded() / 1_000_000
        }
        return CoordinateBounds(
            southWest: Coordinate(
                latitude: snap(southWest.latitude, .down),
                longitude: snap(southWest.longitude, .down)
            ),
            northEast: Coordinate(latitude: snap(northEast.latitude, .up), longitude: snap(northEast.longitude, .up))
        )
    }
}

public extension TransitClient {
    /// The grid ``buses(in:)`` snaps its area to: 0.02°, about 2 km north to south and 1.7 km east to west, so a
    /// map panned a little asks for the same area as before.
    static let busGridStep = 0.02

    /// The MTA buses inside an area, at their GPS positions (`GET /api/vehicles/bus`).
    ///
    /// The area is snapped outward to ``busGridStep``, so the answer may hold buses just outside it. Our server
    /// proxies MTA Bus Time with its key, and the CDN caches each area for 30 seconds.
    ///
    /// - Throws: ``TransitError/server(statusCode:message:)`` with 503 where the server has no Bus Time key, and 502
    ///   where Bus Time is down.
    func buses(in bounds: CoordinateBounds) async throws(TransitError) -> BusPositions {
        let area = bounds.snapped(toGrid: Self.busGridStep)
        let bbox = [
            area.southWest.latitude,
            area.southWest.longitude,
            area.northEast.latitude,
            area.northEast.longitude,
        ]
        .map { "\($0)" }
        .joined(separator: ",")
        let request = HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/api/vehicles/bus?bbox=\(bbox)")
        let operationID = "vehiclesBus"
        do {
            let (response, body) = try await userAgent.intercept(
                request,
                body: nil,
                baseURL: baseURL,
                operationID: operationID,
                next: { [retry, transport] request, body, baseURL in
                    try await retry.intercept(request, body: body, baseURL: baseURL, operationID: operationID) {
                        try await transport.send($0, body: $1, baseURL: $2, operationID: operationID)
                    }
                }
            )
            var data = Data()
            if let body {
                data = try await Data(collecting: body, upTo: 8 * 1024 * 1024)
            }
            guard response.status == .ok else {
                let message = try? JSONDecoder().decode(ServerError.self, from: data).error
                if response.status.code == 429 || message == nil {
                    throw TransitError(
                        undocumentedStatus: response.status.code,
                        payload: UndocumentedPayload(headerFields: response.headerFields, body: nil)
                    )
                }
                throw TransitError.server(statusCode: response.status.code, message: message)
            }
            return try JSONDecoder().decode(BusPositions.self, from: data)
        } catch {
            throw TransitError(error)
        }
    }

    /// How each MTA bus route in an area is named and coloured in the feed, by GTFS `route_id`
    /// (`GET /api/experimental/map/routes`).
    ///
    /// The bus positions endpoint carries route ids alone; this fills in the label and colours. They change only
    /// with the timetables, so keep what it answers rather than asking again for the same routes.
    func busRouteStyles(in bounds: CoordinateBounds, zoom: Double) async throws(TransitError)
        -> [String: BusRouteStyle]
    {
        let area = bounds.snapped(toGrid: Self.busGridStep)
        let query = Operations.Routes.Input.Query(
            zoom: zoom,
            min: "\(area.southWest.latitude),\(area.southWest.longitude)",
            max: "\(area.northEast.latitude),\(area.northEast.longitude)"
        )
        do {
            switch try await client.routes(query: query) {
            case let .ok(success):
                return try BusRouteStyle.styles(from: success.body.json.routes)
            case let .badRequest(error):
                throw TransitError.server(statusCode: 400, message: try? error.body.json.error)
            case let .notFound(error):
                throw TransitError.server(statusCode: 404, message: try? error.body.json.error)
            case let .unprocessableContent(error):
                throw TransitError.server(statusCode: 422, message: try? error.body.json.error)
            case let .internalServerError(error):
                throw TransitError.server(statusCode: 500, message: try? error.body.json.error)
            case let .undocumented(statusCode, payload):
                throw TransitError(undocumentedStatus: statusCode, payload: payload)
            }
        } catch {
            throw TransitError(error)
        }
    }
}

/// The `{ "error": "…" }` our server's own endpoints answer failures with.
private struct ServerError: Decodable {
    var error: String
}
