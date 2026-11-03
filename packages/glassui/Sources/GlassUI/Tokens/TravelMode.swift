import SwiftUI
import UIKit

/// A way of getting around, with its accent colour, symbol, and name for display. GlassUI's own plain value: the app
/// maps TransitKit's modes onto it.
///
/// ```swift
/// Image(systemName: TravelMode.subway.symbolName)
///     .foregroundStyle(TravelMode.subway.onColor)
///     .background(TravelMode.subway.color, in: Radius.shape(Radius.sm))
/// ```
///
/// A mode's accent marks the mode (an icon tile, a walking leg on a route), never a specific line: line colours
/// come from the transit feed.
public enum TravelMode: String, CaseIterable, Identifiable, Sendable {
    case walk
    case bus
    case tram
    case subway
    case rail
    case ferry
    case cableCar = "cable-car"

    public var id: Self {
        self
    }

    /// The mode's name for display.
    public var title: String {
        switch self {
        case .walk: String(localized: "Walk")
        case .bus: String(localized: "Bus")
        case .tram: String(localized: "Tram")
        case .subway: String(localized: "Subway")
        case .rail: String(localized: "Rail")
        case .ferry: String(localized: "Ferry")
        case .cableCar: String(localized: "Cable car")
        }
    }

    /// The SF Symbol for the mode.
    public var symbolName: String {
        switch self {
        case .walk: "figure.walk"
        case .bus: "bus.fill"
        case .tram: "tram.fill"
        case .subway: "tram.fill.tunnel"
        case .rail: "train.side.front.car"
        case .ferry: "ferry.fill"
        case .cableCar: "cablecar.fill"
        }
    }

    /// The mode's accent colour, with light and dark variants.
    public var color: Color {
        switch self {
        case .walk: Color(uiColor: .systemGray)
        case .bus: Color(uiColor: .systemBlue)
        case .tram: Color(uiColor: .systemMint)
        case .subway: Color(uiColor: .systemIndigo)
        case .rail: Color(uiColor: .systemPurple)
        case .ferry: Color(uiColor: .systemCyan)
        case .cableCar: Color(uiColor: .systemOrange)
        }
    }

    /// A legible colour for a symbol or text drawn on ``color``.
    public var onColor: Color {
        switch self {
        case .walk, .bus, .subway, .rail: .white
        case .tram, .ferry, .cableCar: .black
        }
    }
}
