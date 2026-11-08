import GlassUI
import SwiftUI
import TransitKit

/// Journey times as New Yorkers read them: on the city's clock, whatever the device's time zone.
enum JourneyClock {
    static let timeZone = TimeZone(identifier: "America/New_York") ?? .current

    /// A time of day, such as "6:44 PM".
    static func time(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone))
    }

    /// A time of day, with its weekday where it isn't on `now`'s day, such as "Wed 9:00 AM".
    static func dayAndTime(_ date: Date, relativeTo now: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard !calendar.isDate(date, inSameDayAs: now) else { return time(date) }
        let day = date.formatted(Date.FormatStyle(timeZone: timeZone).weekday(.abbreviated))
        return "\(day) \(time(date))"
    }
}

/// How journeys draw TransitKit's lines with GlassUI's components, in the feed's own route colours.
enum JourneyStyle {
    /// The segment bar's legs for a summary.
    static func legs(_ summary: JourneySummary) -> [JourneyLeg] {
        summary.segments.map { segment in
            switch segment.kind {
            case .walk:
                JourneyLeg(id: segment.id, .walk, minutes: segment.minutes)
            case let .ride(bullet, mode):
                JourneyLeg(id: segment.id, .ride(line(bullet, mode: mode)), minutes: segment.minutes)
            }
        }
    }

    /// A line's badge, in the feed's colours where it gives them.
    static func line(_ bullet: LineBullet, mode: TransitMode) -> TransitLine {
        let travelMode = travelMode(mode)
        return TransitLine(
            id: "\(mode.rawValue)-\(bullet.text)-\(bullet.shape)",
            name: bullet.text,
            mode: travelMode,
            color: bullet.color.map(lineColor) ?? fallbackColor(travelMode),
            textColor: bullet.textColor.map(lineColor),
            isExpress: bullet.shape == .diamond
        )
    }

    /// GlassUI's mode for a MOTIS mode.
    static func travelMode(_ mode: TransitMode) -> TravelMode {
        switch mode {
        case .walk: .walk
        case .bus, .coach: .bus
        case .tram: .tram
        case .subway, .metro: .subway
        case .ferry: .ferry
        case .cableCar, .aerialLift, .arealLift, .funicular: .cableCar
        default: .rail
        }
    }

    /// The colour a leg is drawn in on the map: the feed's route colour, else its mode's; walks in grey.
    static func mapColor(_ leg: Leg) -> Color {
        guard leg.tripId != nil else { return TravelMode.walk.color }
        if let color = leg.routeRGBColor {
            return lineColor(color).color
        }
        return travelMode(leg.mode).color
    }

    private static func lineColor(_ color: RGBColor) -> LineColor {
        LineColor(red: color.red, green: color.green, blue: color.blue)
    }

    /// The MTA's own greys and blues, for a line whose feed gives no colour.
    private static func fallbackColor(_ mode: TravelMode) -> LineColor {
        LineColor(hex: mode == .bus ? "0039A6" : "808183") ?? .black
    }
}

extension MapRoute {
    /// An itinerary's legs, each in its line's colour and walks dashed, decoded from MOTIS's polylines.
    init(journey itinerary: Itinerary) {
        self.init(
            id: itinerary.id,
            segments: itinerary.legs.enumerated().map { index, leg in
                let path = leg.coordinates
                return MapRoute.Segment(
                    id: "\(index)",
                    coordinates: path.isEmpty ? [leg.from.coordinate, leg.to.coordinate] : path,
                    color: JourneyStyle.mapColor(leg),
                    isDashed: leg.tripId == nil
                )
            }
        )
    }
}
