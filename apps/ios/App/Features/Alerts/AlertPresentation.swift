import Foundation
import GlassUI
import SwiftUI
import TransitKit

// TransitKit's alerts as GlassUI's plain values and the words around them.

extension ServiceAlertBanner.Level {
    init(_ level: AlertLevel) {
        switch level {
        case .info: self = .info
        case .warning: self = .warning
        case .severe: self = .severe
        }
    }

    /// The heading of a group of lines at this level on line status.
    var groupTitle: LocalizedStringKey {
        switch self {
        case .severe: "Suspended or Stops Skipped"
        case .warning: "Delays and Changes"
        case .info: "Service Notices"
        }
    }
}

extension ServiceAlertBanner {
    /// A banner for `alert`, at its level, with its header as the MTA wrote it.
    init(_ alert: ServiceAlert, lineLimit: Int? = 2, showsChevron: Bool = true) {
        self.init(
            level: Level(alert.level),
            header: alert.displayHeader,
            lineLimit: lineLimit,
            showsChevron: showsChevron
        )
    }
}

extension TransitLine {
    /// A line on line status in the feed's colours: a bullet for a subway line (an `S` for a shuttle), a pill for SIR
    /// and buses ("M14A SBS").
    init(_ line: LineStatusLine) {
        let bullet = line.bullet
        let mode: TravelMode = if line.id == "SI" {
            .rail
        } else if bullet.shape == .label {
            .bus
        } else {
            .subway
        }
        let color = bullet.color.map { LineColor(red: $0.red, green: $0.green, blue: $0.blue) }
        self.init(
            id: line.id,
            name: bullet.text.replacingOccurrences(of: "-SBS", with: " SBS"),
            mode: mode,
            color: color ?? LineColor(red: 0.43, green: 0.43, blue: 0.45),
            textColor: bullet.textColor.map { LineColor(red: $0.red, green: $0.green, blue: $0.blue) },
            accessibilityName: line.name
        )
    }
}

extension AlertPeriod {
    /// The period in New York's time, such as "Nov 14, 11:45 PM – Nov 15, 5:00 AM" or "From Nov 3, 6:00 PM".
    var formatted: String {
        switch (start, end) {
        case let (start?, end?): "\(start.formatted(Self.style)) – \(end.formatted(Self.style))"
        case let (start?, nil): "From \(start.formatted(Self.style)) until further notice"
        case let (nil, end?): "Until \(end.formatted(Self.style))"
        case (nil, nil): "Until further notice"
        }
    }

    /// Dates and times as on the station's signs: New York's, wherever the phone is set.
    private static let style: Date.FormatStyle = {
        var style = Date.FormatStyle(date: .abbreviated, time: .shortened)
        style.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return style
    }()
}

extension FormatStyle where Self == Date.FormatStyle {
    /// A time as on the station's clock, such as "6:30 PM": New York's, wherever the phone is set.
    static var newYorkTime: Date.FormatStyle {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return style
    }
}
