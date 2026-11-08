import Foundation
import GlassUI
import TransitKit

// TransitKit's departures as GlassUI's plain values, which the Nearby section's rows draw.

extension TransitLine {
    /// The line a group of departures rides, in the feed's own colours: a bullet or diamond for subway lines, a
    /// pill for buses ("M14A SBS", which VoiceOver reads as "M14A Select Bus").
    init(_ line: LineDepartures) {
        let bullet = line.bullet
        self.init(
            id: line.id,
            name: bullet.text.replacingOccurrences(of: "-SBS", with: " SBS"),
            mode: TravelMode(line.mode),
            color: bullet.color.map(LineColor.init) ?? .unknownLine,
            textColor: bullet.textColor.map(LineColor.init),
            isExpress: bullet.shape == .diamond
        )
    }
}

extension LineColor {
    init(_ color: RGBColor) {
        self.init(red: color.red, green: color.green, blue: color.blue)
    }

    /// For a line the feed gives no colour: a neutral grey that reads in light and dark.
    static let unknownLine = LineColor(red: 0.43, green: 0.43, blue: 0.45)
}

extension TravelMode {
    init(_ mode: TransitMode) {
        switch mode {
        case .bus, .coach: self = .bus
        case .subway, .metro: self = .subway
        case .tram: self = .tram
        case .ferry: self = .ferry
        case .aerialLift, .arealLift, .cableCar, .funicular: self = .cableCar
        case .walk: self = .walk
        default: self = .rail
        }
    }
}

extension DepartureTime {
    /// A departure's countdown from `now`, styled by how it stands against the timetable; live times read as
    /// uncertain while `realtimeIsStale`.
    init(_ departure: Departure, now: Date, realtimeIsStale: Bool) {
        let status: Status = switch departure.status(realtimeIsStale: realtimeIsStale) {
        case .scheduled: .scheduled
        case .onTime, .early: .live
        case let .late(minutes): .delayed(minutes: minutes)
        case .cancelled: .cancelled
        case .uncertain: .uncertain
        }
        self.init(id: departure.id, minutes: departure.minutesUntil(from: now) ?? 0, status: status)
    }
}

extension LineDepartures {
    /// The line under the headsign: how the next departure stands ("On time", "3 min late"), with the timetable's
    /// time for a scheduled one ("Scheduled · 6:42 PM").
    func detail(realtimeIsStale: Bool) -> String? {
        guard let next = next ?? departures.first else { return nil }
        let status = next.status(realtimeIsStale: realtimeIsStale)
        guard status == .scheduled, let time = next.scheduledTime else { return status.text }
        return "\(status.text) · \(time.formatted(Self.clock))"
    }

    /// Times as on the station's clock: New York's, wherever the phone is set.
    private static let clock: Date.FormatStyle = {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return style
    }()
}
