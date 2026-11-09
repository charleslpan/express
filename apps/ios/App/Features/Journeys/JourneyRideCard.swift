import GlassUI
import SwiftUI
import TransitKit

/// A ride: its line in the feed's colour, headsign, and direction, which opens the vehicle's trip; then the stops it
/// boards and alights at with their times and live status, and the stops between, folded away.
struct JourneyRideCard: View {
    let ride: JourneyRide
    let leg: Leg
    let realtimeIsStale: Bool
    let onShowTrip: () -> Void

    @State private var showsStops: Bool

    init(
        ride: JourneyRide,
        leg: Leg,
        realtimeIsStale: Bool,
        showsStops: Bool = false,
        onShowTrip: @escaping () -> Void
    ) {
        self.ride = ride
        self.leg = leg
        self.realtimeIsStale = realtimeIsStale
        self.onShowTrip = onShowTrip
        _showsStops = State(initialValue: showsStops)
    }

    var body: some View {
        JourneyCard {
            JourneyLegAlertsSlot(leg: leg)
            Button(action: onShowTrip) {
                HStack(alignment: .center, spacing: Spacing.xs) {
                    if let line {
                        LinePill(line)
                    }
                    VStack(alignment: .leading, spacing: Spacing.xxxs) {
                        Text(headsign)
                            .typography(.cardTitle)
                            .foregroundStyle(.textPrimary)
                        Text(subtitle)
                            .typography(.secondary)
                            .foregroundStyle(.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .typography(.secondary)
                        .foregroundStyle(.textTertiary)
                }
                .multilineTextAlignment(.leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(lineLabel)
            .accessibilityHint(ride.mode == .bus ? "Shows where this bus is" : "Shows where this train is")
            .accessibilityIdentifier("journey.trip")
            if ride.isCancelled {
                Label(
                    ride.board.isCancelled || ride.alight.isCancelled ? "Stop Skipped" : "Cancelled",
                    systemImage: "xmark.octagon.fill"
                )
                .typography(.captionEmphasized)
                .foregroundStyle(.statusDisrupted)
            }
            HStack(alignment: .top, spacing: Spacing.sm) {
                Capsule()
                    .fill(lineColor)
                    .frame(width: 4)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    JourneyStopRow(stop: ride.board, role: .board, realtimeIsStale: realtimeIsStale)
                    stopsDisclosure
                    JourneyStopRow(stop: ride.alight, role: .alight, realtimeIsStale: realtimeIsStale)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var stopsDisclosure: some View {
        if ride.intermediateStops.isEmpty {
            Text(ride.formattedStopCount)
                .typography(.secondary)
                .foregroundStyle(.textSecondary)
        } else {
            DisclosureGroup(isExpanded: $showsStops) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    ForEach(ride.intermediateStops) { stop in
                        JourneyStopRow(stop: stop, role: .pass, realtimeIsStale: realtimeIsStale)
                    }
                }
                .padding(.top, Spacing.xxs)
            } label: {
                Text("\(ride.formattedStopCount) · \(ride.formattedDuration)")
                    .typography(.secondary)
            }
            .tint(Color.brand)
            .accessibilityIdentifier("journey.stops")
        }
    }

    private var line: TransitLine? {
        ride.bullet.map { JourneyStyle.line($0, mode: ride.mode) }
    }

    private var lineColor: Color {
        line?.color.color ?? JourneyStyle.travelMode(ride.mode).color
    }

    private var headsign: String {
        ride.headsign.map { String(localized: "to \($0)") } ?? (ride.mode == .bus ? "Bus" : "Train")
    }

    /// "Uptown & The Bronx · 8 min", or the time aboard alone where the direction is unknown.
    private var subtitle: String {
        [ride.direction, ride.formattedDuration].compactMap(\.self).joined(separator: " · ")
    }

    private var lineLabel: String {
        let name = line?.accessibilityName ?? ""
        return [String(localized: "\(name) \(headsign)"), ride.direction, ride.formattedDuration]
            .compactMap(\.self)
            .joined(separator: ", ")
    }
}

/// One stop on a ride: its time, its name, and how the time stands live ("2 min late", "On time"), with the platform
/// or track where the feed gives one.
struct JourneyStopRow: View {
    enum Role {
        case board
        case pass
        case alight
    }

    let stop: JourneyStopTime
    let role: Role
    let realtimeIsStale: Bool

    var body: some View {
        AdaptiveStack(spacing: Spacing.xs) {
            Text(JourneyClock.time(stop.time))
                .typography(role == .pass ? .secondary : .bodyEmphasized)
                .monospacedDigit()
                .foregroundStyle(role == .pass ? Color.textSecondary : Color.textPrimary)
                .strikethrough(stop.isCancelled)
            VStack(alignment: .leading, spacing: Spacing.xxxs) {
                Text(stop.name)
                    .typography(role == .pass ? .secondary : .body)
                    .foregroundStyle(role == .pass ? Color.textSecondary : Color.textPrimary)
                if let note {
                    Text(note)
                        .typography(.captionEmphasized)
                        .foregroundStyle(JourneyText.color(of: status))
                }
            }
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var status: DepartureStatus {
        stop.status(realtimeIsStale: realtimeIsStale)
    }

    /// The live status and track, such as "2 min late · Track 2": nothing for a stop passed on time or on the
    /// timetable alone, so the stops between stay quiet.
    private var note: String? {
        var parts: [String] = []
        switch status {
        case .scheduled: break
        case .onTime: if role != .pass {
                parts.append(status.text)
            }
        default: parts.append(status.text)
        }
        if role == .board, let track = stop.track {
            parts.append(String(localized: "Track \(track)"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var accessibilityLabel: String {
        let time = JourneyClock.time(stop.time)
        let place = switch role {
        case .board: String(localized: "Board at \(stop.name), \(time)")
        case .pass: String(localized: "\(stop.name), \(time)")
        case .alight: String(localized: "Get off at \(stop.name), \(time)")
        }
        return [place, note].compactMap(\.self).joined(separator: ", ")
    }
}
