import SwiftUI

/// One departure's time and how sure it is, as plain values: what ``RealtimeBadge`` and ``DepartureRow`` draw.
public struct DepartureTime: Hashable, Sendable, Identifiable {
    /// Where the time comes from, and what's happening to the trip.
    public enum Status: Hashable, Sendable {
        /// From the timetable.
        case scheduled
        /// From a live feed.
        case live
        /// From a live feed, and running `minutes` late.
        case delayed(minutes: Int)
        /// Cancelled: the trip won't run.
        case cancelled
        /// Meant to be live, but the feed has gone quiet or stale, so it may not be real time.
        case uncertain
    }

    public var id: String
    /// Minutes until it leaves; 0 is now.
    public var minutes: Int
    public var status: Status

    public init(id: String? = nil, minutes: Int, status: Status) {
        self.id = id ?? "\(minutes)-\(status)"
        self.minutes = max(minutes, 0)
        self.status = status
    }

    /// The time as shown: "Now" or "4 min".
    public var text: String {
        minutes == 0 ? String(localized: "Now") : String(localized: "\(minutes) min")
    }

    /// What VoiceOver says: "3 minutes, live".
    public var accessibilityLabel: String {
        let time = minutes == 0
            ? String(localized: "now")
            : String(localized: "\(minutes) minutes", comment: "A departure's countdown, spoken")
        let note = switch status {
        case .scheduled: String(localized: "scheduled")
        case .live: String(localized: "live")
        case let .delayed(late): String(localized: "live, \(late) minutes late")
        case .cancelled: String(localized: "cancelled")
        case .uncertain: String(localized: "may not be real time")
        }
        return "\(time), \(note)"
    }
}

/// A departure time styled by how sure it is: live times in green with a gently pulsing glyph, scheduled times calm
/// and plain, delays in amber, cancellations struck through in red, and a muted "may not be real time" glyph when the
/// live feed has gone quiet.
///
/// ```swift
/// RealtimeBadge(DepartureTime(minutes: 3, status: .live))
/// RealtimeBadge(DepartureTime(minutes: 9, status: .scheduled), prominence: .secondary)
/// ```
///
/// The glyph only pulses where Reduce Motion is off.
public struct RealtimeBadge: View {
    /// How loud the time is.
    public enum Prominence: Sendable {
        /// The next departure: ``Typography/time``.
        case primary
        /// A later departure, beside the next one.
        case secondary
    }

    private let departure: DepartureTime
    private let prominence: Prominence
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ departure: DepartureTime, prominence: Prominence = .primary) {
        self.departure = departure
        self.prominence = prominence
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xxxs) {
            Text(departure.text)
                .font(prominence == .primary ? Typography.time.font : timeSecondaryFont)
                .strikethrough(departure.status == .cancelled, color: Color.statusDisrupted)
                .foregroundStyle(textStyle)
            glyph
                .font(glyphFont)
                // Raised like a superscript, as on a departure board.
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] + $0.height * 0.4 }
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(departure.accessibilityLabel)
    }

    private var timeSecondaryFont: Font {
        .system(.subheadline, design: .rounded, weight: .semibold).monospacedDigit()
    }

    private var glyphFont: Font {
        prominence == .primary ? .system(.caption, weight: .bold) : .system(.caption2, weight: .bold)
    }

    private var textStyle: Color {
        switch departure.status {
        case .live: .statusOnTime
        case .delayed: .statusDelayed
        case .cancelled: .statusDisrupted
        case .scheduled: prominence == .primary ? .textPrimary : .textSecondary
        case .uncertain: .textSecondary
        }
    }

    @ViewBuilder
    private var glyph: some View {
        switch departure.status {
        case .live, .delayed:
            Image(systemName: "dot.radiowaves.up.forward")
                .foregroundStyle(textStyle)
                .symbolEffect(
                    .variableColor.iterative.dimInactiveLayers,
                    options: .repeat(.continuous),
                    isActive: !reduceMotion
                )
        case .uncertain:
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .foregroundStyle(.textTertiary)
        case .scheduled, .cancelled:
            EmptyView()
        }
    }
}

#if DEBUG
    private struct RealtimeBadgePreview: View {
        private let departures = [
            DepartureTime(minutes: 0, status: .live),
            DepartureTime(minutes: 3, status: .live),
            DepartureTime(minutes: 7, status: .delayed(minutes: 4)),
            DepartureTime(minutes: 12, status: .scheduled),
            DepartureTime(minutes: 5, status: .cancelled),
            DepartureTime(minutes: 8, status: .uncertain),
        ]

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(departures) { departure in
                    HStack(spacing: Spacing.md) {
                        RealtimeBadge(departure)
                        RealtimeBadge(departure, prominence: .secondary)
                    }
                }
            }
            .padding()
        }
    }

    #Preview("RealtimeBadge") {
        RealtimeBadgePreview()
    }

    #Preview("RealtimeBadge, dark") {
        RealtimeBadgePreview()
            .preferredColorScheme(.dark)
    }

    #Preview("RealtimeBadge, AX5") {
        RealtimeBadgePreview()
            .dynamicTypeSize(.accessibility5)
    }
#endif
