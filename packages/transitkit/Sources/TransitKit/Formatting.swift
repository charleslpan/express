import Foundation

/// Formats transit durations for display.
public enum DurationFormat {
    /// A duration in seconds as riders read it: "45 sec" under a minute, "7 min", "1 hr 5 min", "2 hr".
    ///
    /// Minutes round to the nearest; English abbreviations until the app localizes.
    public static func string(seconds: Int) -> String {
        if seconds < 60 {
            return "\(max(seconds, 0)) sec"
        }
        let minutes = Int((Double(seconds) / 60).rounded())
        let hours = minutes / 60
        let rest = minutes % 60
        switch (hours, rest) {
        case (0, _): return "\(rest) min"
        case (_, 0): return "\(hours) hr"
        default: return "\(hours) hr \(rest) min"
        }
    }
}

/// Formats walking distances for display.
public enum DistanceFormat {
    /// A distance in metres as New Yorkers read it: feet to the nearest 10 under a tenth of a mile ("450 ft"), else
    /// miles to one decimal ("1.3 mi"). English until the app localizes.
    public static func string(meters: Double) -> String {
        let miles = max(meters, 0) / 1609.344
        if miles < 0.1 {
            let feet = Int((max(meters, 0) * 3.280_84 / 10).rounded()) * 10
            return "\(max(feet, 10)) ft"
        }
        return String(format: "%.1f mi", miles)
    }
}

public extension Itinerary {
    /// The itinerary's duration for display, such as "22 min".
    var formattedDuration: String {
        DurationFormat.string(seconds: duration)
    }
}

public extension Leg {
    /// The leg's duration for display, such as "4 min".
    var formattedDuration: String {
        DurationFormat.string(seconds: duration)
    }
}

/// An sRGB colour with components from 0 to 1, parsed from GTFS hex such as `f6bc26`.
public struct RGBColor: Sendable, Hashable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Parses six hex digits (`RRGGBB`), with or without a leading `#`; `nil` for anything else.
    public init?(hex: String) {
        let digits = hex.hasPrefix("#") ? hex.dropFirst() : Substring(hex)
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit), let value = UInt32(digits, radix: 16) else {
            return nil
        }
        red = Double((value >> 16) & 0xFF) / 255
        green = Double((value >> 8) & 0xFF) / 255
        blue = Double(value & 0xFF) / 255
    }
}

public extension Leg {
    /// The route's colour from the feed (the MTA's official line colours for the subway), if it gives one.
    var routeRGBColor: RGBColor? {
        routeColor.flatMap(RGBColor.init(hex:))
    }

    /// The colour the feed gives for text on ``routeRGBColor``, if any.
    var routeTextRGBColor: RGBColor? {
        routeTextColor.flatMap(RGBColor.init(hex:))
    }
}
