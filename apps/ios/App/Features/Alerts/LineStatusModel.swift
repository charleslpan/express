import Foundation
import Observation
import TransitKit

/// The data behind line status: every subway line's and the nearby buses' alerts from the line status endpoint
/// (``TransitClient/lineStatus(lines:)``), refreshed about every 30 seconds while ``run(client:lines:now:)`` runs.
/// A failed refresh keeps what was shown, which reads as stale once it's a minute old.
@MainActor
@Observable
final class LineStatusModel {
    enum Content: Equatable {
        case loading
        case loaded(LineStatusResponse, fetchedAt: Date)
        /// The last fetch failed with nothing fetched before it to fall back on.
        case failed(TransitError)
    }

    private(set) var content = Content.loading
    /// The time alerts are judged at, updated on every refresh.
    private(set) var now = Date.now

    static let refreshInterval = Duration.seconds(30)
    /// How old the shown alerts may be before the screen says so.
    static let staleAfter: TimeInterval = 60

    /// Refreshes now, then about every ``refreshInterval`` until the calling task is cancelled.
    func run(client: TransitClient, lines: [LineStatusLine], now: () -> Date) async {
        while !Task.isCancelled {
            await refresh(client: client, lines: lines, now: now())
            try? await Task.sleep(for: Self.refreshInterval)
        }
    }

    func refresh(client: TransitClient, lines: [LineStatusLine], now: Date) async {
        self.now = now
        do {
            let response = try await client.lineStatus(lines: lines.flatMap(\.requestIds))
            guard !Task.isCancelled else { return }
            content = .loaded(response, fetchedAt: now)
        } catch {
            guard !Task.isCancelled else { return }
            if case .loaded = content {
                return
            }
            content = .failed(error)
        }
    }

    /// Shows loading again before a retry from the error state.
    func retry() {
        content = .loading
    }

    /// Whether the shown alerts were fetched over a minute ago, because refreshing has failed since.
    var isStale: Bool {
        guard case let .loaded(_, fetchedAt) = content else { return false }
        return now.timeIntervalSince(fetchedAt) > Self.staleAfter
    }
}

/// Line status arranged for the screen: each line under the worst level of its current alerts, or under good
/// service, and the work still to come under upcoming.
struct LineStatusSections {
    struct Row: Equatable, Identifiable {
        var line: LineStatusLine
        /// Its alerts that apply now, the most severe first.
        var alerts: [ServiceAlert]

        var id: String {
            line.id
        }
    }

    struct Upcoming: Equatable, Identifiable {
        var alert: ServiceAlert
        /// The lines it's on, in the screen's order.
        var lines: [LineStatusLine]

        var id: String {
            alert.id
        }
    }

    /// The lines whose worst current alert is at one level.
    struct Group: Equatable, Identifiable {
        var level: AlertLevel
        var rows: [Row]

        var id: AlertLevel {
            level
        }
    }

    /// Lines with current alerts, most severe group first: suspensions, then delays, then notices.
    var groups: [Group]
    /// Lines with nothing that applies now, in the MTA's order.
    var goodService: [LineStatusLine]
    /// Alerts that apply later, soonest first, each once with every line it's on.
    var upcoming: [Upcoming]

    init(lines: [LineStatusLine], response: LineStatusResponse, now: Date) {
        var rows: [Row] = []
        var good: [LineStatusLine] = []
        var upcoming: [Upcoming] = []
        for line in lines {
            let alerts = response.alerts(for: line)
            let current = alerts.active(at: now)
            if current.isEmpty {
                good.append(line)
            } else {
                rows.append(Row(line: line, alerts: current))
            }
            for alert in alerts.upcoming(after: now) {
                if let index = upcoming.firstIndex(where: { $0.alert.id == alert.id }) {
                    upcoming[index].lines.append(line)
                } else {
                    upcoming.append(Upcoming(alert: alert, lines: [line]))
                }
            }
        }
        groups = AlertLevel.allCases.reversed().compactMap { level in
            let matching = rows.filter { $0.alerts.first?.level == level }
            return matching.isEmpty ? nil : Group(level: level, rows: matching)
        }
        goodService = good
        self.upcoming = upcoming.sorted {
            ($0.alert.nextStart(after: now) ?? .distantFuture) < ($1.alert.nextStart(after: now) ?? .distantFuture)
        }
    }

    /// Whether no line has an alert that applies now.
    var isAllGood: Bool {
        groups.isEmpty
    }
}
