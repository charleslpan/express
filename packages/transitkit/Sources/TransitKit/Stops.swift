import Foundation

/// A stop as MOTIS returns it from `map/stops`: a subway platform (with its station as ``Place/parentId``),
/// a bus stop, or a station.
public typealias Stop = Place

public extension Stop {
    /// The id to ask for a stop's departures by: its parent station's where it has one, else its own.
    var stationId: String? {
        parentId ?? stopId
    }

    /// The dataset tag MOTIS prefixes ids with, such as `us-ny-MTA-BusBrooklyn` for `us-ny-MTA-BusBrooklyn_404197`.
    internal var feed: String? {
        guard let stopId, let separator = stopId.firstIndex(of: "_") else { return nil }
        return String(stopId[..<separator])
    }

    /// The stop's id within its feed, such as `404197` for `us-ny-MTA-BusBrooklyn_404197`.
    internal var feedStopId: String? {
        guard let stopId, let separator = stopId.firstIndex(of: "_") else { return nil }
        return String(stopId[stopId.index(after: separator)...])
    }
}

/// A place riders think of as one station: a subway complex's platforms under all its parent stations, or a single
/// bus stop.
public struct Station: Sendable, Hashable, Identifiable {
    /// The id to ask for the station's departures by: the first of ``stopIds``.
    ///
    /// `stoptimes` on one parent of a complex already returns the whole complex's departures.
    public var id: String
    public var name: String
    /// The parent stations the platforms belong to (`635`, `L03`, and `R20` at Union Square), sorted; a bus stop's
    /// own id where it has no parent.
    public var stopIds: [String]
    /// The platforms or stops grouped here, in the order they came.
    public var platforms: [Stop]
    /// The modes that serve the station, in the order the platforms list them.
    public var modes: [TransitMode]
    /// The platforms' mean position.
    public var coordinate: Coordinate

    /// Whether several parent stations make up the station, as at a subway complex such as 14 St-Union Sq.
    public var isComplex: Bool {
        stopIds.count > 1
    }

    /// How far apart two parent stations of the same name may be and still count as one complex, in metres.
    ///
    /// Union Square's 635, L03, and R20 lie within about 120 m of each other; same-named stations on other lines,
    /// such as the several 23 Sts, lie far further apart.
    public static let complexRadius: Double = 300

    init(platforms: [Stop], stopIds: [String]) {
        let ids = stopIds.sorted()
        id = ids[0]
        name = platforms[0].name
        self.stopIds = ids
        self.platforms = platforms
        var modes: [TransitMode] = []
        for mode in platforms.flatMap({ $0.modes ?? [] }) where !modes.contains(mode) {
            modes.append(mode)
        }
        self.modes = modes
        let count = Double(platforms.count)
        coordinate = Coordinate(
            latitude: platforms.map(\.lat).reduce(0, +) / count,
            longitude: platforms.map(\.lon).reduce(0, +) / count
        )
    }
}

public extension Sequence<Stop> {
    /// The stops with the copies dropped that a stop gets when two feeds carry it.
    ///
    /// The MTA's borough bus feeds share stops near their borders: `us-ny-MTA-BusBrooklyn_404197` and
    /// `us-ny-MTA-BusStatenIsland_404197` are the same pole. A stop counts as a copy when an earlier one from another
    /// feed has the same id within its feed and the same name, and stands within 50 m; the first one is kept.
    func deduplicated() -> [Stop] {
        var kept: [Stop] = []
        var seen: [String: [Stop]] = [:]
        for stop in self {
            guard let feedStopId = stop.feedStopId else {
                kept.append(stop)
                continue
            }
            let key = "\(feedStopId)|\(stop.name)"
            let isCopy = seen[key, default: []].contains {
                $0.feed != stop.feed && $0.coordinate.distance(to: stop.coordinate) < 50
            }
            guard !isCopy else { continue }
            seen[key, default: []].append(stop)
            kept.append(stop)
        }
        return kept
    }

    /// The stops, de-duplicated, gathered into the stations riders know: platforms under their parent station, and
    /// same-named parent stations within ``Station/complexRadius`` of each other under one complex.
    ///
    /// Stops without a parent, such as bus stops, are each a station of their own. Stations come in the order their
    /// first platform came.
    func groupedIntoStations(complexRadius: Double = Station.complexRadius) -> [Station] {
        // Platforms under each parent, in the order the parents first appear; parentless stops stand alone.
        var groups: [Group] = []
        var groupIndex: [String: Int] = [:]
        for stop in deduplicated() {
            if let parentId = stop.parentId {
                if let index = groupIndex[parentId] {
                    groups[index].platforms.append(stop)
                } else {
                    groupIndex[parentId] = groups.count
                    groups.append(Group(stopIds: [parentId], platforms: [stop], isStation: true))
                }
            } else {
                let id = stop.stopId ?? "\(stop.lat),\(stop.lon)"
                groups.append(Group(stopIds: [id], platforms: [stop], isStation: false))
            }
        }

        // Same-named parents close together make one complex.
        var stations: [Group] = []
        for group in groups {
            let first = group.platforms[0]
            let match = stations.firstIndex { station in
                group.isStation && station.isStation && station.platforms[0].name == first.name
                    && station.platforms[0].coordinate.distance(to: first.coordinate) <= complexRadius
            }
            if let match {
                stations[match].stopIds += group.stopIds
                stations[match].platforms += group.platforms
            } else {
                stations.append(group)
            }
        }
        return stations.map { Station(platforms: $0.platforms, stopIds: $0.stopIds) }
    }
}

/// Stops gathered under one or more ids while ``Swift/Sequence/groupedIntoStations(complexRadius:)`` works.
private struct Group {
    var stopIds: [String]
    var platforms: [Stop]
    /// Whether the ids are parent stations, which may merge into a complex; a lone bus stop never does.
    var isStation: Bool
}

public extension Coordinate {
    /// The great-circle distance to another coordinate, in metres.
    func distance(to other: Coordinate) -> Double {
        let earthRadius = 6_371_000.0
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let deltaLat = lat2 - lat1
        let deltaLon = (other.longitude - longitude) * .pi / 180
        let haversine = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        return 2 * earthRadius * atan2(sqrt(haversine), sqrt(1 - haversine))
    }
}
