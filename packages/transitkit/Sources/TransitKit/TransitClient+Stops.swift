import Foundation

public extension TransitClient {
    /// Lists a stop's next departures or arrivals (`GET /api/v6/stoptimes`).
    ///
    /// A subway station's id lists its whole complex: `us-ny-MTA-NYCSubway_635` returns the 4, 5, 6, L, N, Q, R,
    /// and W at Union Square.
    func departures(_ request: DeparturesRequest) async throws(TransitError) -> DeparturesResponse {
        do {
            switch try await client.stoptimes(query: request.query) {
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

    /// Lists the stops inside a map area (`GET /api/v6/map/stops`): platforms and bus stops, as MOTIS returns them.
    ///
    /// Gather them with ``Swift/Sequence/groupedIntoStations(complexRadius:)``, or drop the copies two bus feeds give
    /// with ``Swift/Sequence/deduplicated()``.
    ///
    /// - Parameters:
    ///   - southWest: The area's south-west corner (lowest latitude and longitude).
    ///   - northEast: The area's north-east corner.
    ///   - transitModes: The modes whose stops to list, such as `[.subway]`; `nil` lists every one.
    func stops(
        southWest: Coordinate,
        northEast: Coordinate,
        transitModes: [TransitMode]? = nil
    ) async throws(TransitError) -> [Stop] {
        var query = Operations.Stops.Input.Query(
            min: "\(southWest.latitude),\(southWest.longitude)",
            max: "\(northEast.latitude),\(northEast.longitude)"
        )
        query.modes = transitModes
        do {
            switch try await client.stops(query: query) {
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

    /// Fetches a trip with its stops and shape (`GET /api/v6/trip`), as an itinerary of one transit leg.
    ///
    /// - Parameter id: The trip's id, such as a ``Departure``'s `tripId` or a ``Leg``'s.
    func trip(id: String) async throws(TransitError) -> Itinerary {
        do {
            switch try await client.trip(query: .init(tripId: id)) {
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

public extension Itinerary {
    /// The stops a trip calls at in order, from its first to its last: each transit leg's origin, intermediate
    /// stops, and destination, without repeating a stop where one leg ends and the next begins.
    var tripStops: [Place] {
        var stops: [Place] = []
        for leg in transitLegs {
            for place in [leg.from] + (leg.intermediateStops ?? []) + [leg.to] {
                if let last = stops.last, last.stopId != nil, last.stopId == place.stopId {
                    continue
                }
                stops.append(place)
            }
        }
        return stops
    }

    /// The trip's path, decoded from its legs' geometry.
    var coordinates: [Coordinate] {
        legs.flatMap(\.coordinates)
    }
}
