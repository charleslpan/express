import Foundation

/// A path along a polyline, measured so a point can be found at any fraction of its length.
public struct PolylinePath: Sendable, Hashable {
    public let coordinates: [Coordinate]
    /// The distance in metres from the start to each coordinate.
    private let distances: [Double]

    public init(_ coordinates: [Coordinate]) {
        self.coordinates = coordinates
        var distances: [Double] = []
        distances.reserveCapacity(coordinates.count)
        for (index, coordinate) in coordinates.enumerated() {
            distances.append(index == 0 ? 0 : distances[index - 1] + coordinates[index - 1].distance(to: coordinate))
        }
        self.distances = distances
    }

    /// The path's length in metres.
    public var length: Double {
        distances.last ?? 0
    }

    /// The point `fraction` of the way along the path (clamped to 0 through 1), and the bearing of the stretch it lies
    /// on, in degrees clockwise from north; `nil` for an empty path.
    ///
    /// A path of one point, or of points all in one place, answers that point with no bearing.
    public func point(atFraction fraction: Double) -> (coordinate: Coordinate, bearing: Double?)? {
        guard let first = coordinates.first else { return nil }
        guard length > 0 else { return (first, nil) }
        let target = min(max(fraction, 0), 1) * length
        // The first stretch that ends at or past the target and has some length.
        var end = 1
        while end < coordinates.count - 1, distances[end] < target || distances[end] == distances[end - 1] {
            end += 1
        }
        let start = end - 1
        let stretch = distances[end] - distances[start]
        let local = stretch > 0 ? min(max((target - distances[start]) / stretch, 0), 1) : 1
        let from = coordinates[start]
        let to = coordinates[end]
        let coordinate = Coordinate(
            latitude: from.latitude + (to.latitude - from.latitude) * local,
            longitude: from.longitude + (to.longitude - from.longitude) * local
        )
        return (coordinate, stretch > 0 ? from.bearing(to: to) : nil)
    }
}

public extension Coordinate {
    /// The initial great-circle bearing to another coordinate, in degrees clockwise from north (0 up to 360).
    func bearing(to other: Coordinate) -> Double {
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let deltaLon = (other.longitude - longitude) * .pi / 180
        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }
}

/// Where a train is estimated to be at a moment: on the track between two stops, or standing at a stop.
///
/// The subway has no GPS, so this comes from the trip's times at its stops (realtime where the feed predicts them),
/// spread evenly along the track between them.
public struct TrainPosition: Sendable, Hashable, Identifiable, MapLocated {
    /// The trip's id.
    public var id: String
    public var bullet: LineBullet
    public var coordinate: Coordinate
    /// The direction of travel, in degrees clockwise from north.
    public var bearing: Double
    /// The stop the train last left, or stands at.
    public var fromStop: String
    /// The stop the train runs to next; the same as ``fromStop`` while it stands at a stop.
    public var toStop: String
    /// Whether realtime data stands behind the times, rather than the timetable alone.
    public var isRealtime: Bool

    public init(
        id: String,
        bullet: LineBullet,
        coordinate: Coordinate,
        bearing: Double,
        fromStop: String,
        toStop: String,
        isRealtime: Bool
    ) {
        self.id = id
        self.bullet = bullet
        self.coordinate = coordinate
        self.bearing = bearing
        self.fromStop = fromStop
        self.toStop = toStop
        self.isRealtime = isRealtime
    }
}

/// One trip's hops from `map/trips`, decoded once so its position can be read at any moment.
///
/// ```swift
/// let runs = TrainRun.runs(from: try await client.tripSegments(in: bounds, zoom: 14, from: now, to: later))
/// let positions = runs.compactMap { $0.position(at: .now) }
/// ```
public struct TrainRun: Sendable, Identifiable {
    /// The trip's id.
    public let id: String
    public let bullet: LineBullet
    /// The hops in the order the train runs them.
    let hops: [Hop]

    struct Hop: Sendable {
        var path: PolylinePath
        var departure: Date
        var arrival: Date
        var from: Place
        var to: Place
        var isRealtime: Bool
    }

    init(id: String, bullet: LineBullet, hops: [Hop]) {
        self.id = id
        self.bullet = bullet
        self.hops = hops.sorted { $0.departure < $1.departure }
    }

    /// The trips among `segments` in `modes` (the subway by default), each with its hops gathered and decoded.
    public static func runs(from segments: some Sequence<TripSegment>, modes: Set<TransitMode> = [.subway])
        -> [TrainRun]
    {
        var order: [String] = []
        var grouped: [String: (bullet: LineBullet, hops: [Hop])] = [:]
        for segment in segments where modes.contains(segment.mode) {
            guard let id = segment.trips.first?.tripId else { continue }
            var coordinates = segment.coordinates
            if coordinates.count < 2 {
                coordinates = [segment.from.coordinate, segment.to.coordinate]
            }
            let hop = Hop(
                path: PolylinePath(coordinates),
                departure: segment.departure,
                arrival: max(segment.arrival, segment.departure),
                from: segment.from,
                to: segment.to,
                isRealtime: segment.realTime
            )
            if grouped[id] == nil {
                order.append(id)
                grouped[id] = (segment.lineBullet, [hop])
            } else {
                grouped[id]?.hops.append(hop)
            }
        }
        return order.compactMap { id in grouped[id].map { TrainRun(id: id, bullet: $0.bullet, hops: $0.hops) } }
    }

    /// Where the train is estimated to be at `date`; `nil` before its first hop leaves or after its last arrives.
    ///
    /// Between departure and arrival it moves along the hop's track in proportion to the time elapsed. Between
    /// arriving at a stop and leaving it on the next hop it stands at the stop. Where a hop is missing (it ran outside
    /// the area asked for), the train is somewhere off the map, so there's no position.
    public func position(at date: Date) -> TrainPosition? {
        for (index, hop) in hops.enumerated() {
            if date < hop.departure {
                // Standing at this hop's first stop, if the train arrived there on the hop before.
                guard index > 0, hops[index - 1].to.stopId == hop.from.stopId, date >= hops[index - 1].arrival else {
                    return nil
                }
                return position(on: hop, fraction: 0, standing: true)
            }
            if date <= hop.arrival {
                let duration = hop.arrival.timeIntervalSince(hop.departure)
                let fraction = duration > 0 ? date.timeIntervalSince(hop.departure) / duration : 1
                return position(on: hop, fraction: fraction, standing: false)
            }
        }
        return nil
    }

    private func position(on hop: Hop, fraction: Double, standing: Bool) -> TrainPosition? {
        guard let point = hop.path.point(atFraction: fraction) else { return nil }
        let bearing = point.bearing
            ?? hop.path.point(atFraction: 1).flatMap(\.bearing)
            ?? hop.from.coordinate.bearing(to: hop.to.coordinate)
        return TrainPosition(
            id: id,
            bullet: bullet,
            coordinate: point.coordinate,
            bearing: bearing,
            fromStop: hop.from.name,
            toStop: standing ? hop.from.name : hop.to.name,
            isRealtime: hop.isRealtime
        )
    }
}

/// Something with an id and a place on the map, such as a train or a bus, for ``TrainVisibility`` to thin.
public protocol MapLocated {
    var id: String { get }
    var coordinate: Coordinate { get }
}

/// Which vehicles a map shows (trains or buses), so the whole city's never crowd it.
public typealias VehicleVisibility = TrainVisibility

/// Which trains a map shows, so the whole city's never crowd it; buses use it too, as ``VehicleVisibility``.
public struct TrainVisibility: Sendable, Hashable {
    /// The zoom level from which trains show: about 13, where a phone's screen spans a few kilometres of Manhattan.
    public var minimumZoom: Double
    /// The most trains shown at once; past it, those nearest the middle of the map win.
    public var limit: Int

    public init(minimumZoom: Double = 13, limit: Int = 120) {
        self.minimumZoom = minimumZoom
        self.limit = limit
    }

    /// Whether trains show at `zoom` at all, and so whether they're worth fetching.
    public func showsTrains(atZoom zoom: Double) -> Bool {
        zoom >= minimumZoom
    }

    /// Whether vehicles show at `zoom` at all, as ``showsTrains(atZoom:)`` says for trains.
    public func showsVehicles(atZoom zoom: Double) -> Bool {
        showsTrains(atZoom: zoom)
    }

    /// The positions to show on a map looking at `bounds` at `zoom`: none when zoomed out past ``minimumZoom``, else
    /// those inside `bounds`, thinned to the ``limit`` nearest its centre.
    public func visible<Position: MapLocated>(
        _ positions: some Sequence<Position>,
        in bounds: CoordinateBounds,
        zoom: Double
    ) -> [Position] {
        guard showsTrains(atZoom: zoom) else { return [] }
        let inside = positions.filter { bounds.contains($0.coordinate) }
        guard inside.count > limit else { return inside }
        let center = bounds.center
        let byDistance: [(position: Position, distance: Double)] = inside.map {
            ($0, $0.coordinate.distance(to: center))
        }
        let nearest = byDistance.sorted { lhs, rhs in
            lhs.distance == rhs.distance ? lhs.position.id < rhs.position.id : lhs.distance < rhs.distance
        }
        return nearest.prefix(limit).map(\.position)
    }
}
