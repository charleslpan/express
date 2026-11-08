/// How a line is drawn in a bullet: what it says, its shape, and its colours from the feed.
///
/// The MTA draws subway lines in circles and their express variants (6X, 7X, FX) in diamonds, both labelled with the
/// line alone ("6"); buses and other lines read as their route name ("B57", "SIR").
public struct LineBullet: Sendable, Hashable {
    /// The bullet's outline.
    public enum Shape: Sendable, Hashable {
        /// A subway line's circle.
        case circle
        /// A subway express variant's diamond.
        case diamond
        /// A rounded label, for buses and every other line.
        case label
    }

    /// The text inside: the subway line without its express `X` ("6" for 6X), else the route name ("B57").
    public var text: String
    public var shape: Shape
    /// The fill, as the feed gives it (the MTA's current official palette); `nil` where the feed gives none.
    public var color: RGBColor?
    /// The text colour, as the feed gives it; `nil` where the feed gives none.
    public var textColor: RGBColor?

    public init(text: String, shape: Shape, color: RGBColor? = nil, textColor: RGBColor? = nil) {
        self.text = text
        self.shape = shape
        self.color = color
        self.textColor = textColor
    }

    /// The prefix of route ids from the MTA subway's feed (`us-ny-MTA-NYCSubway_6X`), the Staten Island Railway's
    /// among them.
    static let subwayRoutePrefix = "us-ny-MTA-NYCSubway_"

    /// Whether a subway route's short name or id is an express variant: one line letter or digit and an `X`,
    /// such as `6X`, `7X`, and `FX`.
    public static func isExpressVariant(_ route: String) -> Bool {
        route.count == 2 && route.last == "X" && route.first.map { $0.isNumber || $0.isUppercase } == true
    }

    /// The bullet for a line named `name` (its short name, else long name), from its mode, route id, and colours.
    static func make(
        name: String,
        mode: TransitMode,
        routeId: String?,
        color: RGBColor?,
        textColor: RGBColor?
    ) -> LineBullet {
        let routeCode = routeId.flatMap { id in
            id.hasPrefix(subwayRoutePrefix) ? String(id.dropFirst(subwayRoutePrefix.count)) : nil
        }
        guard mode == .subway || (routeCode != nil && name.count <= 2) else {
            return LineBullet(text: name, shape: .label, color: color, textColor: textColor)
        }
        let isExpress = isExpressVariant(name) || routeCode.map(isExpressVariant) == true
        let text = isExpressVariant(name) ? String(name.dropLast()) : name
        return LineBullet(text: text, shape: isExpress ? .diamond : .circle, color: color, textColor: textColor)
    }
}

public extension Leg {
    /// The leg's bullet: a circle or, for an express variant, a diamond for subway lines, else a label; with the
    /// feed's colours. `nil` for legs that ride no line (walks and other street legs).
    var lineBullet: LineBullet? {
        guard tripId != nil, let name = lineName else { return nil }
        return LineBullet.make(
            name: name,
            mode: mode,
            routeId: routeId,
            color: routeRGBColor,
            textColor: routeTextRGBColor
        )
    }
}

public extension Departure {
    /// The departure's line as a bullet, as for a ``Leg``: a circle or diamond for subway lines, else a label.
    var lineBullet: LineBullet? {
        lineName.map {
            LineBullet.make(name: $0, mode: mode, routeId: routeId, color: routeRGBColor, textColor: routeTextRGBColor)
        }
    }
}
