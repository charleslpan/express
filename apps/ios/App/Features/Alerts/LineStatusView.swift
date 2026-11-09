import GlassUI
import SwiftUI
import TransitKit

/// Line status, pushed onto the home sheet from the alert chip: every subway line, then the bus routes near the
/// rider, each under the worst level of the alerts that apply now (suspended or stops skipped, delays and changes,
/// service notices) or under good service, and the work still to come under upcoming, with its dates. Alerts read as
/// the MTA wrote them; tapping one opens its full text.
///
/// It loads from the line status endpoint, refreshes about every 30 seconds while on screen, says so when what it
/// shows is over a minute old, and offers Try Again when it can't load.
struct LineStatusView: View {
    let nearbyBuses: [LineStatusLine]
    @State private var model = LineStatusModel()
    /// Bumped by "Try Again", which restarts loading.
    @State private var attempt = 0
    @Environment(AppRouter.self) private var router
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.transitClient) private var transitClient
    @Environment(\.scenePhase) private var scenePhase

    private var lines: [LineStatusLine] {
        LineStatusLine.subway + nearbyBuses
    }

    var body: some View {
        content
            .navigationTitle("Line Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarVisibility(.visible, for: .navigationBar)
            .task(id: RefreshKey(isActive: scenePhase == .active, attempt: attempt)) {
                guard scenePhase == .active else { return }
                await model.run(client: transitClient, lines: lines) { environment.now }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.content {
        case .loading:
            ProgressView("Loading line status")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("line-status.loading")
        case let .failed(error):
            ContentUnavailableView {
                Label(
                    error == .offline ? "You're Offline" : "Can't Load Line Status",
                    systemImage: error == .offline ? "wifi.slash" : "exclamationmark.triangle"
                )
            } description: {
                Text(error == .offline
                    ? "Line status will show once you're connected."
                    : "Express couldn't reach its server. Try again in a moment.")
            } actions: {
                Button("Try Again") {
                    model.retry()
                    attempt += 1
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
            }
            .accessibilityIdentifier("line-status.failed")
        case let .loaded(response, fetchedAt):
            let sections = LineStatusSections(lines: lines, response: response, now: model.now)
            list(sections, fetchedAt: fetchedAt)
                .accessibilityIdentifier(sections.isAllGood ? "line-status.all-good" : "line-status.loaded")
        }
    }

    private func list(_ sections: LineStatusSections, fetchedAt: Date) -> some View {
        List {
            Section {
                if model.isStale {
                    StaleNotice(fetchedAt: fetchedAt)
                } else if sections.isAllGood {
                    Label {
                        Text("Good service on every line")
                            .foregroundStyle(.textPrimary)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.statusOnTime)
                    }
                    .typography(.bodyEmphasized)
                }
            } footer: {
                Text("Updated \(fetchedAt.formatted(.newYorkTime)). Alerts from the MTA.")
            }
            ForEach(sections.groups) { group in
                Section {
                    ForEach(group.rows) { row in
                        AlertLineRow(line: row.line, alerts: row.alerts)
                    }
                } header: {
                    Text(ServiceAlertBanner.Level(group.level).groupTitle)
                }
            }
            if !sections.goodService.isEmpty {
                Section("Good Service") {
                    ForEach(sections.goodService) { line in
                        GoodServiceRow(line: line)
                    }
                }
            }
            if !sections.upcoming.isEmpty {
                Section("Upcoming") {
                    ForEach(sections.upcoming) { upcoming in
                        UpcomingRow(upcoming: upcoming, now: model.now)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable {
            await model.refresh(client: transitClient, lines: lines, now: environment.now)
        }
    }

    private struct RefreshKey: Equatable {
        var isActive: Bool
        var attempt: Int
    }
}

/// A line with alerts that apply now: its bullet and name, then a banner per alert, each opening its full text.
private struct AlertLineRow: View {
    let line: LineStatusLine
    let alerts: [ServiceAlert]
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            LineName(line: line)
            ForEach(alerts) { alert in
                Button {
                    router.showAlerts([alert], on: line)
                } label: {
                    ServiceAlertBanner(alert, lineLimit: 3)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows the alert's full text.")
            }
        }
        .padding(.vertical, Spacing.xxs)
    }
}

/// A line with nothing that applies now.
private struct GoodServiceRow: View {
    let line: LineStatusLine

    var body: some View {
        AdaptiveStack(spacing: Spacing.sm) {
            LineName(line: line)
            Spacer(minLength: 0)
            Label("Good service", systemImage: "checkmark.circle")
                .typography(.secondary)
                .foregroundStyle(.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Work still to come: its header, the lines it's on, and when it applies.
private struct UpcomingRow: View {
    let upcoming: LineStatusSections.Upcoming
    let now: Date
    @Environment(AppRouter.self) private var router

    var body: some View {
        Button {
            router.showAlerts([upcoming.alert], on: upcoming.lines.count == 1 ? upcoming.lines.first : nil)
        } label: {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.xxs) {
                    ForEach(upcoming.lines) { line in
                        LinePill(TransitLine(line), size: .compact)
                    }
                }
                .accessibilityHidden(true)
                ServiceAlertBanner(upcoming.alert, lineLimit: 3)
                ForEach(Array(upcoming.alert.remainingPeriods(after: now).prefix(3).enumerated()), id: \.offset) {
                    Text($0.element.formatted)
                        .typography(.caption)
                        .foregroundStyle(.textSecondary)
                }
            }
            .padding(.vertical, Spacing.xxs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows the work's full text.")
    }
}

/// A line's bullet, with its name where the bullet doesn't say it ("42 St Shuttle").
struct LineName: View {
    let line: LineStatusLine

    var body: some View {
        HStack(spacing: Spacing.xs) {
            LinePill(TransitLine(line))
            if let name = line.name {
                Text(name)
                    .typography(.cardTitle)
                    .foregroundStyle(.textPrimary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TransitLine(line).accessibilityName)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Says the alerts shown are over a minute old, since refreshing has failed.
private struct StaleNotice: View {
    let fetchedAt: Date

    var body: some View {
        Label {
            Text("Alerts may be out of date. Last updated \(fetchedAt.formatted(.newYorkTime)).")
                .foregroundStyle(.textPrimary)
        } icon: {
            Image(systemName: "clock.badge.exclamationmark")
                .foregroundStyle(.statusDelayed)
        }
        .typography(.secondary)
        .accessibilityIdentifier("line-status.stale")
    }
}
