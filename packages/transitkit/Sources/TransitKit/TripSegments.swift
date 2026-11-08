import Foundation

/// One hop of a trip between two consecutive stops, as MOTIS's `map/trips` returns it: the stops, the departure and
/// arrival (realtime where the feed has predictions), and the track between them as a polyline.
public typealias TripSegment = Components.Schemas.TripSegment

/// A rectangle of the map, from its south-west corner to its north-east corner. Express never crosses the
/// antimeridian, so it doesn't handle that.
public struct CoordinateBounds: Sendable, Hashable {
    public var southWest: Coordinate
    public var northEast: Coordinate

    public init(southWest: Coordinate, northEast: Coordinate) {
        self.southWest = southWest
        self.northEast = northEast
    }

    /// The point halfway between the corners.
    public var center: Coordinate {
        Coordinate(
            latitude: (southWest.latitude + northEast.latitude) / 2,
            longitude: (southWest.longitude + northEast.longitude) / 2
        )
    }

    /// Whether `coordinate` lies inside, edges included.
    public func contains(_ coordinate: Coordinate) -> Bool {
        (southWest.latitude ... northEast.latitude).contains(coordinate.latitude)
            && (southWest.longitude ... northEast.longitude).contains(coordinate.longitude)
    }

    /// The bounds grown on every side by `fraction` of their height and width, such as `0.25` to also cover what's
    /// just off screen.
    public func padded(by fraction: Double) -> CoordinateBounds {
        let latitude = (northEast.latitude - southWest.latitude) * fraction
        let longitude = (northEast.longitude - southWest.longitude) * fraction
        return CoordinateBounds(
            southWest: Coordinate(latitude: southWest.latitude - latitude, longitude: southWest.longitude - longitude),
            northEast: Coordinate(latitude: northEast.latitude + latitude, longitude: northEast.longitude + longitude)
        )
    }
}

public extension TransitClient {
    /// The precision ``tripSegments(in:zoom:from:to:)`` asks polylines in, which ``TripSegment/coordinates`` decodes
    /// them at: 5, which MOTIS recommends from zoom 11 in.
    static let tripSegmentPrecision = 5

    /// Lists the hops of every trip that runs inside a map area during a time window (`GET /api/v6/map/trips`).
    ///
    /// Times include realtime delays. MOTIS thins trips by zoom (only long-distance trains far out), and returns every
    /// mode; pick the subway with ``TrainRun/runs(from:modes:)``.
    ///
    /// - Parameters:
    ///   - bounds: The area to list trips in.
    ///   - zoom: The map's zoom level.
    ///   - start: The window's start.
    ///   - end: The window's end.
    func tripSegments(
        in bounds: CoordinateBounds,
        zoom: Double,
        from start: Date,
        to end: Date
    ) async throws(TransitError) -> [TripSegment] {
        var query = Operations.Trips.Input.Query(
            zoom: zoom,
            min: "\(bounds.southWest.latitude),\(bounds.southWest.longitude)",
            max: "\(bounds.northEast.latitude),\(bounds.northEast.longitude)",
            startTime: start,
            endTime: end
        )
        query.precision = Double(Self.tripSegmentPrecision)
        do {
            switch try await client.trips(query: query) {
            case let .ok(success):
                return try success.body.json
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

public extension TripSegment {
    /// The hop's track, decoded at ``TransitClient/tripSegmentPrecision``; empty where it doesn't decode.
    var coordinates: [Coordinate] {
        EncodedPolyline(points: polyline, precision: TransitClient.tripSegmentPrecision, length: 0).coordinates
    }

    /// The line's bullet: its name from the trip ("Q", "6X" as a diamond "6"), in the feed's route colour.
    ///
    /// `map/trips` sends no text colour, so it's black or white, whichever reads better on the route colour.
    var lineBullet: LineBullet {
        let name = trips.first.flatMap { $0.displayName ?? $0.routeShortName } ?? ""
        let isExpress = LineBullet.isExpressVariant(name)
        let color = routeColor.flatMap(RGBColor.init(hex:))
        let shape: LineBullet.Shape = mode == .subway ? (isExpress ? .diamond : .circle) : .label
        return LineBullet(
            text: mode == .subway && isExpress ? String(name.dropLast()) : name,
            shape: shape,
            color: color,
            textColor: color.map(\.readableTextColor)
        )
    }
}

public extension RGBColor {
    /// Text on this colour as the MTA sets it: black on light colours such as the yellow N, Q, R, and W, white on
    /// every other line (the green, orange, lime, and grey bullets among them).
    var readableTextColor: RGBColor {
        relativeLuminance > 0.4 ? RGBColor(red: 0, green: 0, blue: 0) : RGBColor(red: 1, green: 1, blue: 1)
    }

    /// The colour's relative luminance, from 0 (black) to 1 (white), as WCAG defines it.
    var relativeLuminance: Double {
        func linear(_ component: Double) -> Double {
            component <= 0.040_45 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}
