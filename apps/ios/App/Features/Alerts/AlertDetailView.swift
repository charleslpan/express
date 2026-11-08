import GlassUI
import SwiftUI
import TransitKit

/// The full text of a line's alerts, as the MTA wrote them: each alert's level, header, description, and when it
/// applies. Pushed onto the home sheet from a banner (``AppRouter/showAlerts(_:on:)``).
struct AlertDetailView: View {
    let alerts: [ServiceAlert]
    let line: LineStatusLine?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if let line {
                    LineName(line: line)
                }
                ForEach(alerts) { alert in
                    AlertText(alert: alert)
                    if alert.id != alerts.last?.id {
                        Divider()
                    }
                }
                Text("Alerts from the MTA.")
                    .typography(.caption)
                    .foregroundStyle(.textSecondary)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(alerts.count == 1 ? "Service Alert" : "Service Alerts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.visible, for: .navigationBar)
        .accessibilityIdentifier("alerts.detail")
    }
}

/// One alert in full.
private struct AlertText: View {
    let alert: ServiceAlert
    @Environment(AppEnvironment.self) private var environment

    /// The periods not yet over, soonest first.
    private var periods: [AlertPeriod] {
        alert.remainingPeriods(after: environment.now)
    }

    var body: some View {
        let level = ServiceAlertBanner.Level(alert.level)
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label {
                Text(alert.isPlanned ? "Planned work · \(level.accessibilityName)" : level.accessibilityName)
                    .foregroundStyle(.textSecondary)
            } icon: {
                Image(systemName: level.systemImage)
                    .foregroundStyle(level.color)
            }
            .typography(.captionEmphasized)
            Text(alert.displayHeader)
                .typography(.bodyEmphasized)
                .foregroundStyle(.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let description = alert.description {
                Text(description)
                    .typography(.body)
                    .foregroundStyle(.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !periods.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("When")
                        .typography(.captionEmphasized)
                        .foregroundStyle(.textSecondary)
                    ForEach(Array(periods.prefix(6).enumerated()), id: \.offset) {
                        Text($0.element.formatted)
                            .typography(.secondary)
                            .foregroundStyle(.textPrimary)
                    }
                    if periods.count > 6 {
                        Text("And \(periods.count - 6) more")
                            .typography(.secondary)
                            .foregroundStyle(.textSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .textSelection(.enabled)
    }
}

/// The view for each ``AlertsDestination``, which ``HomeSheet`` registers for its stack.
struct AlertsDestinationView: View {
    let destination: AlertsDestination

    var body: some View {
        switch destination {
        case let .lineStatus(nearbyBuses): LineStatusView(nearbyBuses: nearbyBuses)
        case let .alerts(alerts, line): AlertDetailView(alerts: alerts, line: line)
        }
    }
}
