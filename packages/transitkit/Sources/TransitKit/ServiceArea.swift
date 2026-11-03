/// A latitude–longitude box that Express serves, for telling whether a place is somewhere it can plan from or to.
public struct ServiceArea: Sendable, Hashable {
    /// The box's southern edge, in degrees.
    public var south: Double
    /// The box's western edge, in degrees.
    public var west: Double
    /// The box's northern edge, in degrees.
    public var north: Double
    /// The box's eastern edge, in degrees.
    public var east: Double

    public init(south: Double, west: Double, north: Double, east: Double) {
        self.south = south
        self.west = west
        self.north = north
        self.east = east
    }

    /// New York City's five boroughs and the nearby New Jersey shore (Newark, Jersey City, Hoboken, Fort Lee):
    /// the area the MTA subway and buses serve, with a margin, so Express v1 covers it.
    public static let nyc = ServiceArea(south: 40.47, west: -74.30, north: 40.95, east: -73.68)

    /// Whether the point lies in the box, edges included.
    public func contains(latitude: Double, longitude: Double) -> Bool {
        (south ... north).contains(latitude) && (west ... east).contains(longitude)
    }

    /// Whether the coordinate lies in the box, edges included.
    public func contains(_ coordinate: Coordinate) -> Bool {
        contains(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}
