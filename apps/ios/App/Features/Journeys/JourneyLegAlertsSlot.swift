import GlassUI
import SwiftUI
import TransitKit

/// The spot at the top of each leg in a journey's plan where its service alerts go: those that apply while the rider
/// would be on the leg (``TransitKit/Leg/applicableAlerts``, by the leg's own times, not "now"), each once, the most
/// severe first, as banners that open the alert's full text (``AppRouter/showAlerts(_:on:)``). Above them, a ride
/// whose boarding or alighting stop an alert says is skipped says so ("Trains skip 42 St").
///
/// Alerts are warn-only: they never change the plan. It draws nothing, and takes no room, where none applies.
struct JourneyLegAlertsSlot: View {
    /// The leg the alerts are for, as MOTIS planned it (and as the latest refresh left it).
    let leg: Leg
    @Environment(AppRouter.self) private var router

    var body: some View {
        let alerts = leg.applicableAlerts
        let skipped = leg.skippedStops
        if !alerts.isEmpty || !skipped.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(skipped, id: \.role) { stop in
                    Label {
                        Text(JourneyAlertText.skipped(stop, mode: leg.mode))
                            .foregroundStyle(.textPrimary)
                    } icon: {
                        Image(systemName: ServiceAlertBanner.Level.severe.systemImage)
                            .foregroundStyle(ServiceAlertBanner.Level.severe.color)
                    }
                    .typography(.secondary)
                    .fontWeight(.semibold)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(JourneyAlertText.skippedAccessibilityLabel(stop, mode: leg.mode))
                    .accessibilityIdentifier("journey.stop-skipped")
                }
                ForEach(alerts) { alert in
                    Button {
                        router.showAlerts([alert], on: line)
                    } label: {
                        ServiceAlertBanner(alert)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows the alert's full text.")
                    .accessibilityIdentifier("journey.alert")
                }
            }
        }
    }

    /// The ride's line, for the alert's full text; `nil` for a walk.
    private var line: LineStatusLine? {
        guard let routeId = leg.routeId, var bullet = leg.lineBullet else { return nil }
        // Line status draws an express variant as its line.
        if bullet.shape == .diamond {
            bullet.shape = .circle
        }
        return LineStatusLine(id: LineStatusLine.lineId(routeId: routeId), bullet: bullet, name: nil)
    }
}

/// The words journeys use for alerts.
enum JourneyAlertText {
    /// What a skipped stop's callout says, such as "Trains skip Grand Central-42 St".
    static func skipped(_ stop: SkippedStop, mode: TransitMode) -> String {
        JourneyStyle.travelMode(mode) == .bus
            ? String(localized: "Buses skip \(stop.name)")
            : String(localized: "Trains skip \(stop.name)")
    }

    /// The callout for VoiceOver, with where the rider gets on or off.
    static func skippedAccessibilityLabel(_ stop: SkippedStop, mode: TransitMode) -> String {
        switch stop.role {
        case .board: String(localized: "\(skipped(stop, mode: mode)), where you get on")
        case .alight: String(localized: "\(skipped(stop, mode: mode)), where you get off")
        }
    }

    /// What an option's flag says, such as "Alert on the 7 train. This journey may be affected; it isn't rerouted."
    /// for a severe alert on a ride, or "Delays or changes on the 4 train".
    static func flag(_ flag: JourneyAlertFlag) -> String {
        let names = flag.lines
            .map { JourneyStyle.line($0.bullet, mode: $0.mode).accessibilityName }
            .formatted(.list(type: .and))
        if flag.mayAffectJourney {
            return String(localized: "Alert on the \(names). This journey may be affected; it isn't rerouted.")
        }
        guard !flag.lines.isEmpty else {
            return String(localized: "Service notice on this journey")
        }
        return switch flag.level {
        case .severe: String(localized: "Alert on the \(names)")
        case .warning: String(localized: "Delays or changes on the \(names)")
        case .info: String(localized: "Service notice on the \(names)")
        }
    }
}

/// A journey option's alert flag (``TransitKit/JourneyAlertFlag``): the icon and colour of its most severe alert, and
/// which lines it's on, as a small tinted label under the option's legs. Part of the option's one VoiceOver element.
struct JourneyAlertFlagLabel: View {
    let flag: JourneyAlertFlag
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let level = ServiceAlertBanner.Level(flag.level)
        Label {
            Text(JourneyAlertText.flag(flag))
                .foregroundStyle(.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: level.systemImage)
                .foregroundStyle(level.color)
        }
        .typography(.caption)
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, Spacing.xxs)
        .background(level.color.opacity(reduceTransparency ? 0.22 : 0.14), in: Radius.shape(Radius.sm))
    }
}
