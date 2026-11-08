/// Which way a subway train runs, as the MTA signs its platforms in Manhattan ("Uptown & The Bronx").
enum SubwayDirection {
    /// Each line's northbound and southbound labels, from the MTA's station list at its Manhattan stations.
    static let labels: [String: (north: String, south: String)] = [
        "1": ("Uptown & The Bronx", "Downtown"),
        "2": ("Uptown & The Bronx", "Downtown & Brooklyn"),
        "3": ("Uptown", "Downtown & Brooklyn"),
        "4": ("Uptown & The Bronx", "Downtown & Brooklyn"),
        "5": ("Uptown & The Bronx", "Downtown & Brooklyn"),
        "6": ("Uptown & The Bronx", "Downtown"),
        "7": ("Queens", "Manhattan"),
        "A": ("Uptown", "Downtown & Brooklyn"),
        "C": ("Uptown", "Downtown & Brooklyn"),
        "E": ("Uptown & Queens", "Downtown"),
        "B": ("Uptown & The Bronx", "Downtown & Brooklyn"),
        "D": ("Uptown & The Bronx", "Downtown & Brooklyn"),
        "F": ("Uptown & Queens", "Downtown & Brooklyn"),
        "M": ("Uptown & Queens", "Downtown & Brooklyn"),
        "N": ("Uptown & Queens", "Downtown & Brooklyn"),
        "Q": ("Uptown & Queens", "Downtown & Brooklyn"),
        "R": ("Uptown & Queens", "Downtown & Brooklyn"),
        "W": ("Uptown & Queens", "Downtown"),
        "G": ("Queens", "Brooklyn"),
        "J": ("Brooklyn & Queens", "Manhattan"),
        "Z": ("Brooklyn & Queens", "Manhattan"),
        "L": ("Manhattan", "Brooklyn"),
    ]

    /// The label for `line` boarding at a subway platform, whose id ends in `N` or `S` (`…NYCSubway_635N`); `nil`
    /// for buses, shuttles, and lines or platforms Express doesn't know.
    static func label(line: String?, stopId: String?) -> String? {
        guard let line, let stopId, stopId.hasPrefix(LineBullet.subwayRoutePrefix),
              let labels = labels[LineBullet.isExpressVariant(line) ? String(line.prefix(1)) : line]
        else { return nil }
        switch stopId.last {
        case "N": return labels.north
        case "S": return labels.south
        default: return nil
        }
    }
}
