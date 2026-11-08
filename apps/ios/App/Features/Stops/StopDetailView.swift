import GlassUI
import SwiftUI
import TransitKit

/// A stop's full departures board, pushed in the home sheet (``AppRouter/showStop(_:)``): the stop's name with its
/// lines as bullets in the feed's colours, a place for service alerts (``StopAlertsSlot``), then every line and
/// direction that calls there in a fixed order (``StopBoard``), each with its upcoming departures, live countdowns,
/// and delays. Tapping a departure follows that vehicle's trip (``AppRouter/showTrip(_:)``).
///
/// It refreshes about every 30 seconds while it shows and the app is active, says so once times may not be real
/// time, and says plainly when there's nothing more today or the times can't be fetched.
struct StopDetailView: View {
    let route: StopRoute

    @State private var model = StopModel()
    /// Bumped by "Try Again", which restarts refreshing.
    @State private var attempt = 0
    @Environment(AppRouter.self) private var router
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.transitClient) private var transitClient
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                StopAlertsSlot(stopId: route.stopId)
                content
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("stop.\(state.identifier)")
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // The name heads the content, where it wraps at any text size; the bar keeps it for the back button.
        .navigationTitle(route.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
            }
        }
        .task(id: refresh) {
            guard refresh.isActive else { return }
            await model.run(client: transitClient, stopId: route.stopId, now: { environment.now })
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            ModeIcon(route.isSubway ? .subway : .bus, style: .tile)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(route.name)
                    .typography(.sectionTitle)
                    .foregroundStyle(.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if case let .loaded(board) = model.content, !board.distinctLines.isEmpty {
                    let lines = board.distinctLines.map(TransitLine.init)
                    FlowLayout(spacing: Spacing.xxs) {
                        ForEach(lines) { line in
                            LinePill(line)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        String(localized: "Lines: \(lines.map(\.accessibilityName).formatted(.list(type: .and)))")
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            StopLoadingRows()
        case let .failed(error):
            StopsFailureMessage(error: error, subject: "Departures") {
                attempt += 1
            }
        case .empty:
            StopsMessage(
                "No More Departures Today",
                systemImage: "moon.zzz",
                message: Text("Nothing else is due to leave this stop today.")
            )
        case let .loaded(board, realtimeIsStale):
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if realtimeIsStale {
                    StopsNotRealTimeNotice(identifier: "stop.not-real-time")
                }
                ForEach(board.lines) { line in
                    StopLineSection(line: line, now: model.now, realtimeIsStale: realtimeIsStale) { departure in
                        router.showTrip(TripRoute(tripId: departure.tripId, stationId: route.stopId))
                    }
                }
            }
        }
    }

    private var state: StopState {
        switch model.content {
        case .idle, .loading: .loading
        case let .failed(error): .failed(error)
        case let .loaded(board):
            board.isEmpty ? .empty : .loaded(board, realtimeIsStale: board.mayNotBeRealTime(at: model.now))
        }
    }

    /// Refreshing runs while the app is active and the About sheet doesn't cover the board.
    private var refresh: StopsRefreshKey {
        StopsRefreshKey(isActive: scenePhase == .active && router.sheet == nil, attempt: attempt)
    }
}

/// What the stop screen shows.
private enum StopState: Equatable {
    case loading
    case loaded(StopBoard, realtimeIsStale: Bool)
    case empty
    case failed(TransitError)

    /// The suffix of the content's accessibility identifier (`stop.loaded`), which the screenshot harness waits on.
    var identifier: String {
        switch self {
        case .loading: "loading"
        case .loaded: "loaded"
        case .empty: "empty"
        case .failed: "failed"
        }
    }
}

/// Where service alerts for the stop go, between its name and its departures. Empty until alert banners (A3) fill
/// it from the stop's id.
struct StopAlertsSlot: View {
    let stopId: String

    var body: some View {
        EmptyView()
    }
}

/// One line in one direction at the stop: its bullet and headsign, then a row per upcoming departure.
struct StopLineSection: View {
    let line: LineDepartures
    let now: Date
    let realtimeIsStale: Bool
    let onSelect: (Departure) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack(spacing: Spacing.xs) {
                LinePill(TransitLine(line))
                Text(line.displayHeadsign)
                    .typography(.cardTitle)
                    .foregroundStyle(.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(TransitLine(line).accessibilityName) to \(line.displayHeadsign)")
            .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(line.departures.enumerated()), id: \.element.id) { index, departure in
                    Button {
                        onSelect(departure)
                    } label: {
                        StopDepartureRow(departure: departure, now: now, realtimeIsStale: realtimeIsStale)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Follows this \(line.mode == .bus ? "bus" : "train") stop by stop.")
                    if index < line.departures.count - 1 {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, Spacing.sm)
            .background(.fill.quaternary, in: Radius.shape(Radius.md))
        }
    }
}

/// One departure: its countdown, styled by how sure it is, then the clock time and how it stands against the
/// timetable ("3 min late"). At accessibility sizes the time moves under the countdown.
struct StopDepartureRow: View {
    let departure: Departure
    let now: Date
    let realtimeIsStale: Bool

    var body: some View {
        let status = departure.status(realtimeIsStale: realtimeIsStale)
        HStack(spacing: Spacing.sm) {
            AdaptiveStack(spacing: Spacing.sm) {
                RealtimeBadge(DepartureTime(departure, now: now, realtimeIsStale: realtimeIsStale))
                VStack(alignment: .leading, spacing: Spacing.xxxs) {
                    if let time = departure.time {
                        Text(time, format: .stationClock)
                            .typography(.secondary)
                            .foregroundStyle(.textPrimary)
                            .monospacedDigit()
                    }
                    Text(status.text)
                        .typography(.caption)
                        .foregroundStyle(status.color)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.forward")
                .typography(.secondary)
                .foregroundStyle(.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, Spacing.xs)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(status: status))
    }

    private func accessibilityLabel(status: DepartureStatus) -> String {
        let countdown = DepartureTime(departure, now: now, realtimeIsStale: realtimeIsStale).accessibilityLabel
        let clock = departure.time.map { $0.formatted(.stationClock) } ?? ""
        return "\(countdown), \(clock), \(status.spokenText)"
    }
}

/// The stop screen while its departures load: two lines' rows in their placeholder state, so it keeps its shape.
private struct StopLoadingRows: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            section(TransitLine(name: "L", mode: .subway, color: .unknownLine), headsign: "8 Av", minutes: [3, 9])
            section(TransitLine(name: "4", mode: .subway, color: .unknownLine), headsign: "Woodlawn", minutes: [6])
        }
        .redacted(reason: .placeholder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading departures")
    }

    private func section(_ line: TransitLine, headsign: String, minutes: [Int]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack(spacing: Spacing.xs) {
                LinePill(line)
                Text(verbatim: headsign).typography(.cardTitle)
            }
            VStack(spacing: 0) {
                ForEach(minutes, id: \.self) { minutes in
                    HStack(spacing: Spacing.sm) {
                        RealtimeBadge(DepartureTime(minutes: minutes, status: .live))
                        VStack(alignment: .leading, spacing: Spacing.xxxs) {
                            Text(verbatim: "6:42 PM").typography(.secondary)
                            Text(verbatim: "On time").typography(.caption)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, Spacing.xs)
                    .frame(minHeight: 44)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .background(.fill.quaternary, in: Radius.shape(Radius.md))
        }
    }
}
