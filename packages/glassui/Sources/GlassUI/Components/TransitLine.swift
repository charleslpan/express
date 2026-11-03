import SwiftUI

/// A line's colour as the feed gives it (GTFS `route_color` and `route_text_color` are sRGB hex), with what GlassUI
/// needs to draw legible text on it.
///
/// ```swift
/// let red = LineColor(hex: "EE352E")       // the 1, 2, and 3
/// Text("1").foregroundStyle(red.legibleText.color)
/// ```
public struct LineColor: Hashable, Sendable {
    /// The sRGB components, each from 0 to 1.
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    /// A colour from a six-digit hex string such as `"EE352E"` or `"#EE352E"`; `nil` where it isn't one.
    public init?(hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") {
            digits.removeFirst()
        }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            return nil
        }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    public static let black = LineColor(red: 0, green: 0, blue: 0)
    public static let white = LineColor(red: 1, green: 1, blue: 1)

    /// The colour, to draw with.
    public var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue)
    }

    /// WCAG 2's relative luminance, from 0 (black) to 1 (white).
    public var relativeLuminance: Double {
        func linear(_ component: Double) -> Double {
            component <= 0.040_45 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG 2's contrast ratio between this colour and `other`, from 1 to 21.
    public func contrastRatio(with other: LineColor) -> Double {
        let (lighter, darker) = (
            max(relativeLuminance, other.relativeLuminance),
            min(relativeLuminance, other.relativeLuminance)
        )
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// White or black, whichever reads on this colour: white wherever it reaches 3:1 (WCAG's minimum for bold
    /// badge-sized text), as transit signage prefers, and otherwise the one with more contrast. Black lands on
    /// light colours such as the N, Q, R, and W's yellow.
    public var legibleText: LineColor {
        if contrastRatio(with: .white) >= 3 {
            return .white
        }
        return contrastRatio(with: .black) > contrastRatio(with: .white) ? .black : .white
    }
}

/// A transit line or route, as plain values: what ``LinePill``, ``DepartureRow``, and ``JourneySegmentBar`` draw.
/// The app maps TransitKit's routes onto it.
///
/// ```swift
/// TransitLine(name: "6", mode: .subway, color: LineColor(hex: "00933C")!, isExpress: true)   // the <6>
/// TransitLine(name: "M15 SBS", mode: .bus, color: LineColor(hex: "2850AD")!)
/// ```
public struct TransitLine: Hashable, Sendable, Identifiable {
    /// The badge a line is drawn as.
    public enum BadgeStyle: Hashable, Sendable {
        /// A round bullet, the subway's local services (the 1, A, L).
        case bullet
        /// A diamond bullet, the subway's express variants (the <6>, <7>).
        case diamond
        /// A rounded rectangle that fits its name, for buses and anything with a longer name (M15, SIR).
        case pill
    }

    public var id: String
    /// The name on the badge, such as `"A"`, `"6"` (for the <6> too), `"M15 SBS"`, or `"SIR"`.
    public var name: String
    public var mode: TravelMode
    /// The line's colour from the feed.
    public var color: LineColor
    /// The text colour from the feed, where it gives one.
    public var textColor: LineColor?
    /// Whether this is an express variant drawn as a diamond, such as the <6> and <7>.
    public var isExpress: Bool
    /// What VoiceOver says for the line, such as "M15 Select Bus" or "6 express train".
    public var accessibilityName: String

    /// A line. `accessibilityName` defaults to a spoken form of `name` for its mode; `textColor` to black or white,
    /// whichever reads on `color`.
    public init(
        id: String? = nil,
        name: String,
        mode: TravelMode,
        color: LineColor,
        textColor: LineColor? = nil,
        isExpress: Bool = false,
        accessibilityName: String? = nil
    ) {
        self.id = id ?? (isExpress ? "\(name)X" : name)
        self.name = name
        self.mode = mode
        self.color = color
        self.textColor = textColor
        self.isExpress = isExpress
        self.accessibilityName = accessibilityName
            ?? Self.spokenName(name: name, mode: mode, isExpress: isExpress)
    }

    /// The colour of the text on the badge: the feed's, or black or white for contrast.
    public var resolvedTextColor: LineColor {
        textColor ?? color.legibleText
    }

    /// A subway service with a one-character name is a bullet (a diamond when express); everything else a pill.
    public var badgeStyle: BadgeStyle {
        guard mode == .subway, name.count == 1 else {
            return .pill
        }
        return isExpress ? .diamond : .bullet
    }

    static func spokenName(name: String, mode: TravelMode, isExpress: Bool) -> String {
        switch mode {
        case .subway:
            return isExpress ? "\(name) express train" : "\(name) train"
        case .bus:
            if name.hasSuffix(" SBS") {
                return "\(name.dropLast(4)) Select Bus"
            }
            // Express buses: BxM, BM, QM, SIM, and X routes.
            let expressPrefixes = ["BxM", "BM", "QM", "SIM", "X"]
            let isExpressBus = expressPrefixes.contains { prefix in
                name.hasPrefix(prefix) && name.dropFirst(prefix.count).first?.isNumber == true
            }
            return isExpressBus ? "\(name) Express Bus" : "\(name) bus"
        case .rail where name == "SIR":
            return "Staten Island Railway"
        default:
            return isExpress ? "\(name) express" : name
        }
    }
}
