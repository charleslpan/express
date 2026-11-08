import GlassUI
import SwiftUI
import TransitKit
import UIKit

/// The stops the trip calls at, as a line in the trip's colour: passed stops greyed out, the vehicle drawn on the
/// line between the two stops it runs between (or on the stop it stands at), and the stop it was opened from marked.
struct TripStopList: View {
    let progress: TripProgress
    let bullet: LineBullet?
    let mode: TransitMode
    /// The station the trip was opened from, which the list marks.
    let stationId: String?
    let realtimeIsStale: Bool

    /// The id the list scrolls to: the vehicle where it's running, else the next stop.
    static func focusID(_ progress: TripProgress) -> String {
        if let vehicle = progress.vehicle, !vehicle.isAtStop {
            return vehicleID
        }
        return progress.nextStop?.id ?? progress.stops.last?.id ?? vehicleID
    }

    static let vehicleID = "trip.vehicle"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(progress.stops.enumerated()), id: \.element.id) { index, stop in
                if let vehicle = progress.vehicle, !vehicle.isAtStop, vehicle.toIndex == index {
                    TripVehicleRow(
                        line: line,
                        color: color,
                        from: progress.stops[vehicle.fromIndex].name,
                        to: stop.name
                    )
                    .id(Self.vehicleID)
                }
                TripStopRow(
                    stop: stop,
                    position: index == 0 ? .first : index == progress.stops.count - 1 ? .last : .middle,
                    isPassed: progress.isPassed(index),
                    // The line above a stop is passed once the stop is reached.
                    isReached: progress.isPassed(index) || isStanding(at: index),
                    hasVehicle: isStanding(at: index),
                    isMarked: stationId.map { stop.place.parentId == $0 || stop.place.stopId == $0 } ?? false,
                    line: line,
                    color: color,
                    realtimeIsStale: realtimeIsStale
                )
                .id(stop.id)
            }
        }
    }

    /// Whether the vehicle stands at the stop at `index`.
    private func isStanding(at index: Int) -> Bool {
        progress.vehicle.map { $0.isAtStop && $0.fromIndex == index } ?? false
    }

    private var line: TransitLine? {
        bullet.map { TransitLine(bullet: $0, mode: mode) }
    }

    private var color: Color {
        bullet?.color.map { LineColor($0).color } ?? LineColor.unknownLine.color
    }
}

/// Where a stop sits on the trip, which decides how much of the line its marker draws.
enum TripStopPosition {
    case first
    case middle
    case last
}

/// The column the trip's line runs down, beside each stop.
private enum TripTimeline {
    /// The column's width.
    static let width: CGFloat = 28
    /// The line's width.
    static let lineWidth: CGFloat = 5
    /// A stop's dot.
    static let dot: CGFloat = 13
    /// Passed stretches of line and passed stops' dots.
    static let passed = Color(uiColor: .systemGray3)
}

/// One stop on the trip: a dot on the line, its name, and its live time and delay.
private struct TripStopRow: View {
    let stop: TripStop
    let position: TripStopPosition
    let isPassed: Bool
    /// Whether the vehicle has got to the stop, so the line above it is passed.
    let isReached: Bool
    let hasVehicle: Bool
    let isMarked: Bool
    let line: TransitLine?
    let color: Color
    let realtimeIsStale: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let status = stop.status(realtimeIsStale: realtimeIsStale)
        Group {
            // At accessibility sizes the time moves under the name, so names never break mid-word.
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    names
                    times(status: status, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .center, spacing: Spacing.sm) {
                    names
                    Spacer(minLength: Spacing.xs)
                    times(status: status, alignment: .trailing)
                        .fixedSize()
                }
            }
        }
        .padding(.vertical, Spacing.xs)
        .padding(.leading, TripTimeline.width + Spacing.xs)
        .frame(minHeight: 44)
        .background(alignment: .leading) {
            marker
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(status: status))
    }

    private var names: some View {
        VStack(alignment: .leading, spacing: Spacing.xxxs) {
            Text(stop.name)
                .typography(isMarked || hasVehicle ? .bodyEmphasized : .body)
                .foregroundStyle(isPassed ? Color.textTertiary : Color.textPrimary)
                .strikethrough(stop.isCancelled)
                .fixedSize(horizontal: false, vertical: true)
            if hasVehicle {
                Text(line?.mode == .bus ? LocalizedStringKey("The bus is here") : "The train is here")
                    .typography(.captionEmphasized)
                    .foregroundStyle(.textSecondary)
            } else if isMarked {
                Text("Where you're looking from")
                    .typography(.caption)
                    .foregroundStyle(.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func times(status: DepartureStatus, alignment: HorizontalAlignment) -> some View {
        if let time = stop.time {
            VStack(alignment: alignment, spacing: Spacing.xxxs) {
                Text(time, format: .stationClock)
                    .typography(.secondary)
                    .monospacedDigit()
                    .foregroundStyle(isPassed ? Color.textTertiary : Color.textPrimary)
                if !isPassed {
                    Text(status.shortText)
                        .typography(.caption)
                        .foregroundStyle(status.color)
                }
            }
        }
    }

    /// The line through the stop, passed above or below it as the vehicle has got, and the stop's dot, or the line's
    /// bullet where the vehicle stands at it.
    private var marker: some View {
        ZStack {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isReached ? TripTimeline.passed : color)
                    .opacity(position == .first ? 0 : 1)
                Rectangle()
                    .fill(isPassed ? TripTimeline.passed : color)
                    .opacity(position == .last ? 0 : 1)
            }
            .frame(width: TripTimeline.lineWidth)
            if hasVehicle, let line {
                LinePill(line, size: .compact)
            } else {
                Circle()
                    .fill(Color(uiColor: .systemBackground))
                    .stroke(isPassed ? TripTimeline.passed : color, lineWidth: 3)
                    .frame(width: TripTimeline.dot, height: TripTimeline.dot)
            }
        }
        .frame(width: TripTimeline.width)
        .accessibilityHidden(true)
    }

    private func accessibilityLabel(status: DepartureStatus) -> String {
        var parts = [stop.name]
        if let time = stop.time {
            parts.append(time.formatted(.stationClock))
        }
        if isPassed {
            parts.append(String(localized: "passed"))
        } else {
            parts.append(status.spokenText)
        }
        if hasVehicle {
            parts.append(String(localized: "the \(line?.mode == .bus ? "bus" : "train") is here"))
        }
        if isMarked {
            parts.append(String(localized: "where you're looking from"))
        }
        return parts.joined(separator: ", ")
    }
}

/// The vehicle on the line between two stops: its bullet on the line, and where it is in words.
private struct TripVehicleRow: View {
    let line: TransitLine?
    let color: Color
    let from: String
    let to: String

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Text("Between \(from) and \(to)")
                .typography(.captionEmphasized)
                .foregroundStyle(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.xs)
        .padding(.leading, TripTimeline.width + Spacing.xs)
        .frame(minHeight: 36)
        .background(alignment: .leading) {
            ZStack {
                VStack(spacing: 0) {
                    Rectangle().fill(TripTimeline.passed)
                    Rectangle().fill(color)
                }
                .frame(width: TripTimeline.lineWidth)
                if let line {
                    LinePill(line, size: .compact)
                } else {
                    Image(systemName: "tram.fill")
                        .foregroundStyle(color)
                }
            }
            .frame(width: TripTimeline.width)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Now between \(from) and \(to), estimated"))
    }
}
