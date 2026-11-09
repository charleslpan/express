import GlassUI
import SwiftUI
import TransitKit

// The pieces of a journey's plan: its summary, a walk, a ride, the transfer between rides, and the notice when the
// journey no longer works. Each is a plain fill rather than glass, since the plan sits in the sheet's glass.

/// The journey at a glance, at the top of its plan: when it leaves and arrives, how long it takes, its legs on a
/// segment bar, and its walking and transfers.
struct JourneyDetailSummary: View {
    let summary: JourneySummary

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            AdaptiveStack(spacing: Spacing.xs) {
                Text(verbatim: "\(JourneyClock.time(summary.departure)) – \(JourneyClock.time(summary.arrival))")
                    .typography(.time)
                    .foregroundStyle(.textPrimary)
                Spacer(minLength: 0)
                Text(summary.formattedDuration)
                    .typography(.time)
                    .foregroundStyle(.textSecondary)
            }
            JourneySegmentBar(legs: JourneyStyle.legs(summary))
            Label(JourneyText.details(summary), systemImage: "figure.walk")
                .typography(.caption)
                .foregroundStyle(.textSecondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isHeader)
    }

    private var accessibilityLabel: String {
        let departs = JourneyClock.time(summary.departure)
        let arrives = JourneyClock.time(summary.arrival)
        return [
            String(localized: "\(departs) to \(arrives), \(summary.formattedDuration)"),
            JourneyStyle.legs(summary).map(\.accessibilityLabel).joined(separator: String(localized: ", then ")),
            JourneyText.details(summary),
        ].joined(separator: ", ")
    }
}

/// A walk at the start or end of the journey: where to, how long, how far, and its turn-by-turn instructions folded
/// away where MOTIS gives them.
struct JourneyWalkCard: View {
    let walk: JourneyWalk
    let leg: Leg
    /// The journey's end as the rider named it, for a walk to MOTIS's `END`.
    let destination: String?

    @State private var showsDirections = false

    var body: some View {
        JourneyCard {
            JourneyLegAlertsSlot(leg: leg)
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                ModeIcon(.walk)
                    .foregroundStyle(.textSecondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxxs) {
                    Text(title)
                        .typography(.cardTitle)
                        .foregroundStyle(.textPrimary)
                    Text(details)
                        .typography(.secondary)
                        .foregroundStyle(.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
            if !walk.instructions.isEmpty {
                DisclosureGroup(isExpanded: $showsDirections) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        ForEach(walk.instructions) { instruction in
                            AdaptiveStack(spacing: Spacing.xxs) {
                                Text(instruction.text)
                                    .foregroundStyle(.textPrimary)
                                Spacer(minLength: 0)
                                Text(instruction.formattedDistance)
                                    .foregroundStyle(.textSecondary)
                            }
                            .typography(.secondary)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(.top, Spacing.xs)
                } label: {
                    Text("Directions")
                        .typography(.secondary)
                }
                .tint(Color.brand)
            }
        }
    }

    private var title: String {
        let name = walk.to == "END" ? destination : walk.to
        return name.map { String(localized: "Walk to \($0)") } ?? String(localized: "Walk to your destination")
    }

    /// "4 min · 0.2 mi".
    private var details: String {
        [walk.formattedDuration, walk.formattedDistance].compactMap(\.self).joined(separator: " · ")
    }
}

/// The change between two rides: where, the walk, and the wait, tinted amber where it's tight and red where live
/// times say it's already missed.
struct JourneyTransferRow: View {
    let transfer: JourneyTransfer

    @ScaledMetric(relativeTo: .subheadline) private var gap = Spacing.xs

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: gap) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxxs) {
                Text(title)
                    .typography(.bodyEmphasized)
                    .foregroundStyle(.textPrimary)
                Text(details)
                    .typography(.secondary)
                    .foregroundStyle(.textSecondary)
                if let warning {
                    Text(warning)
                        .typography(.captionEmphasized)
                        .foregroundStyle(tint)
                }
            }
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: Radius.shape(Radius.sm))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(transfer.status == .comfortable ? "journey.transfer" : "journey.transfer-tight")
    }

    private var title: String {
        transfer.changesStation
            ? String(localized: "Transfer to \(transfer.to)")
            : String(localized: "Transfer at \(transfer.to)")
    }

    /// "2 min walk · 1 min wait".
    private var details: String {
        [transfer.formattedWalk, transfer.formattedWait].compactMap(\.self).joined(separator: " · ")
    }

    private var warning: String? {
        switch transfer.status {
        case .comfortable: nil
        case .tight: String(localized: "Tight connection")
        case .missed: String(localized: "Connection missed on live times")
        }
    }

    private var symbol: String {
        switch transfer.status {
        case .comfortable: "arrow.triangle.swap"
        case .tight: "exclamationmark.triangle.fill"
        case .missed: "xmark.octagon.fill"
        }
    }

    private var tint: Color {
        switch transfer.status {
        case .comfortable: .textSecondary
        case .tight: .statusDelayed
        case .missed: .statusDisrupted
        }
    }

    private var background: AnyShapeStyle {
        switch transfer.status {
        case .comfortable: AnyShapeStyle(.fill.quaternary)
        case .tight: AnyShapeStyle(Color.statusDelayed.opacity(0.14))
        case .missed: AnyShapeStyle(Color.statusDisrupted.opacity(0.14))
        }
    }
}

/// The notice that the journey no longer works on live times, such as a cancelled train, with the way back to the
/// other options.
struct JourneyProblemNotice: View {
    let problem: JourneyProblem
    let onSeeOptions: () -> Void

    @ScaledMetric(relativeTo: .headline) private var gap = Spacing.xs

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: gap) {
                Image(systemName: "xmark.octagon.fill")
                    .foregroundStyle(.statusDisrupted)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("This Journey Won't Work")
                        .typography(.cardTitle)
                        .foregroundStyle(.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text(problem.message)
                        .typography(.secondary)
                        .foregroundStyle(.textPrimary)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            Button("See Other Journeys", action: onSeeOptions)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .typography(.button)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.statusDisrupted.opacity(0.14), in: Radius.shape(Radius.md))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("journey.problem")
    }
}

/// A step's card: a plain fill in the sheet's glass, its content stacked.
struct JourneyCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            content
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.quaternary, in: Radius.shape(Radius.md))
    }
}

/// Words the plan shares between its pieces.
enum JourneyText {
    /// "7 min walk · 1 transfer".
    static func details(_ summary: JourneySummary) -> String {
        let walk = String(localized: "\(summary.formattedWalking) walk")
        guard !summary.isWalkOnly else { return walk }
        let transfers = switch summary.transfers {
        case 0: String(localized: "no transfers")
        case 1: String(localized: "1 transfer")
        default: String(localized: "\(summary.transfers) transfers")
        }
        return "\(walk) · \(transfers)"
    }

    /// The colour a stop's status reads in: green on time or early, amber late, red cancelled, else secondary.
    static func color(of status: DepartureStatus) -> Color {
        switch status {
        case .onTime, .early: .statusOnTime
        case .late: .statusDelayed
        case .cancelled: .statusDisrupted
        case .scheduled, .uncertain: .textSecondary
        }
    }
}
