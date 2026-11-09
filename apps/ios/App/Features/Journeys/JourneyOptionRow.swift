import GlassUI
import SwiftUI
import TransitKit

/// One journey option: how long it takes, when it leaves and arrives, its legs on a segment bar, its walking and
/// transfers, and when the first ride leaves, live where realtime data stands behind it. The selected option (the one
/// on the map) is tinted, and an option with an alert on one of its legs is flagged. VoiceOver reads it as one button.
struct JourneyOptionRow: View {
    let summary: JourneySummary
    let now: Date
    let isSelected: Bool
    /// Whether the list says its times may not be real time, which mutes the live badge.
    let mayNotBeRealTime: Bool
    /// The option's alert flag: its most severe alert that applies while the rider would be on a leg; `nil` for none.
    var alertFlag: JourneyAlertFlag?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                AdaptiveStack(spacing: Spacing.xs) {
                    VStack(alignment: .leading, spacing: Spacing.xxxs) {
                        Text(summary.formattedDuration)
                            .typography(.time)
                            .foregroundStyle(.textPrimary)
                        Text(
                            verbatim: "\(JourneyClock.time(summary.departure)) – \(JourneyClock.time(summary.arrival))"
                        )
                        .typography(.secondary)
                        .foregroundStyle(.textSecondary)
                    }
                    Spacer(minLength: 0)
                    if let departure {
                        VStack(alignment: .trailing, spacing: Spacing.xxxs) {
                            Text("Leaves in")
                                .typography(.caption)
                                .foregroundStyle(.textSecondary)
                            RealtimeBadge(departure, prominence: .secondary)
                        }
                    }
                }
                JourneySegmentBar(legs: JourneyStyle.legs(summary))
                if let alertFlag {
                    JourneyAlertFlagLabel(flag: alertFlag)
                }
                Label(details, systemImage: "figure.walk")
                    .typography(.caption)
                    .foregroundStyle(.textSecondary)
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? AnyShapeStyle(Color.brand.opacity(0.14)) : AnyShapeStyle(.fill.quaternary),
                in: Radius.shape(Radius.md)
            )
            .overlay {
                if isSelected {
                    Radius.shape(Radius.md).strokeBorder(Color.brand, lineWidth: 2)
                }
            }
            .contentShape(Radius.shape(Radius.md))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Shows this journey step by step, and on the map")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// When the first ride leaves, as a badge; nil for a journey on foot.
    private var departure: DepartureTime? {
        guard !summary.isWalkOnly else { return nil }
        let status: DepartureTime.Status = if mayNotBeRealTime, summary.isRealtime {
            .uncertain
        } else if let delay = summary.firstRideDelayMinutes, delay > 0 {
            .delayed(minutes: delay)
        } else if summary.isRealtime {
            .live
        } else {
            .scheduled
        }
        return DepartureTime(minutes: summary.minutesUntilDeparture(from: now), status: status)
    }

    /// "7 min walk · 1 transfer".
    private var details: String {
        let walk = String(localized: "\(summary.formattedWalking) walk")
        guard !summary.isWalkOnly else { return walk }
        let transfers = switch summary.transfers {
        case 0: String(localized: "no transfers")
        case 1: String(localized: "1 transfer")
        default: String(localized: "\(summary.transfers) transfers")
        }
        return "\(walk) · \(transfers)"
    }

    private var accessibilityLabel: String {
        let departs = JourneyClock.time(summary.departure)
        let arrives = JourneyClock.time(summary.arrival)
        var parts = [
            String(localized: "\(summary.formattedDuration), \(departs) to \(arrives)"),
            JourneyStyle.legs(summary).map(\.accessibilityLabel).joined(separator: String(localized: ", then ")),
            details,
        ]
        if let departure {
            parts.append(String(localized: "leaves in \(departure.accessibilityLabel)"))
        }
        if let alertFlag {
            parts.append(JourneyAlertText.flag(alertFlag))
        }
        return parts.joined(separator: ", ")
    }
}
