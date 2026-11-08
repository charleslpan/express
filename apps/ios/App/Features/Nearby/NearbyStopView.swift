import GlassUI
import SwiftUI
import TransitKit

/// A nearby stop and its next departures: a header with the stop's mode, name, and walk, then a row per line and
/// direction, soonest first. Tapping a row opens that line's departures (``AppRouter/showDepartures(_:at:)``).
struct NearbyStopView: View {
    let departures: NearbyDepartures
    /// How many lines to show; nil for all of them.
    let lineLimit: Int?
    let now: Date
    let realtimeIsStale: Bool
    /// Whether the home sheet's peek ends at this stop's first rows: the nearest station's next trains.
    let marksPeek: Bool
    let onSelect: (LineDepartures) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .headline) private var gap = Spacing.xs

    init(
        departures: NearbyDepartures,
        lineLimit: Int?,
        now: Date,
        realtimeIsStale: Bool,
        marksPeek: Bool,
        onSelect: @escaping (LineDepartures) -> Void
    ) {
        self.departures = departures
        self.lineLimit = lineLimit
        self.now = now
        self.realtimeIsStale = realtimeIsStale
        self.marksPeek = marksPeek
        self.onSelect = onSelect
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            header
            VStack(spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                    Button {
                        onSelect(line)
                    } label: {
                        DepartureRow(
                            line: TransitLine(line),
                            headsign: line.displayHeadsign,
                            detail: line.detail(realtimeIsStale: realtimeIsStale),
                            departures: line.departures.map {
                                DepartureTime($0, now: now, realtimeIsStale: realtimeIsStale)
                            }
                        )
                    }
                    .buttonStyle(.plain)
                    .homeSheetPeekBoundary(marksPeek && index == peekRow)
                    if index < lines.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    private var lines: [LineDepartures] {
        lineLimit.map { Array(departures.lines.prefix($0)) } ?? departures.lines
    }

    /// The last row the peek shows: the second, or only the first at accessibility sizes, where rows grow tall.
    private var peekRow: Int {
        dynamicTypeSize.isAccessibilitySize ? 0 : min(1, lines.count - 1)
    }

    private var header: some View {
        let stop = departures.stop
        return HStack(spacing: gap) {
            ModeIcon(stop.isSubway ? .subway : .bus, style: .tile)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxxs) {
                Text(stop.displayName)
                    .typography(.cardTitle)
                    .foregroundStyle(.textPrimary)
                Text("\(stop.walkingMinutes) min walk")
                    .typography(.secondary)
                    .foregroundStyle(.textSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(stop.displayName), \(stop.isSubway ? "subway station" : "bus stop"), \(stop.walkingMinutes) minute walk"
        )
        .accessibilityAddTraits(.isHeader)
    }
}

/// A message in place of the Nearby section's departures, such as "Location Is Off", with what the rider can do
/// about it. It marks the end of the home sheet's peek, so the whole message shows there.
struct NearbyMessage<Actions: View>: View {
    private let title: LocalizedStringKey
    private let systemImage: String
    private let message: LocalizedStringKey
    private let actions: Actions

    init(
        _ title: LocalizedStringKey,
        systemImage: String,
        message: LocalizedStringKey,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.systemImage = systemImage
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Label {
                    Text(title)
                        .foregroundStyle(.textPrimary)
                } icon: {
                    Image(systemName: systemImage)
                        .foregroundStyle(.textSecondary)
                }
                .typography(.cardTitle)
                Text(message)
                    .typography(.secondary)
                    .foregroundStyle(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            actions
                .typography(.button)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
        }
        .padding(Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The sheet brings the glass; a plain fill sits inside it.
        .background(.fill.tertiary, in: Radius.shape(Radius.lg))
        .homeSheetPeekBoundary()
    }
}

/// The Nearby section while it finds stops or loads departures: a stop's header and rows in their placeholder
/// state, so the section keeps its shape.
struct NearbyLoadingRows: View {
    let label: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack(spacing: Spacing.xs) {
                ModeIcon(.subway, style: .tile)
                VStack(alignment: .leading, spacing: Spacing.xxxs) {
                    Text(verbatim: "14 St-Union Sq").typography(.cardTitle)
                    Text(verbatim: "2 min walk").typography(.secondary)
                }
            }
            VStack(spacing: 0) {
                ForEach(Self.rows.indices, id: \.self) { index in
                    let row = Self.rows[index]
                    DepartureRow(line: row.line, headsign: row.headsign, departures: row.departures)
                        .homeSheetPeekBoundary(index == 1)
                    Divider()
                }
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private struct Row {
        var line: TransitLine
        var headsign: String
        var departures: [DepartureTime]
    }

    /// Plausible rows to draw redacted, so the placeholder has a departure list's shape.
    private static let rows = [
        Row(
            line: TransitLine(name: "L", mode: .subway, color: .unknownLine),
            headsign: "8 Av",
            departures: [DepartureTime(minutes: 3, status: .live), DepartureTime(minutes: 9, status: .scheduled)]
        ),
        Row(
            line: TransitLine(name: "4", mode: .subway, color: .unknownLine),
            headsign: "Woodlawn",
            departures: [DepartureTime(minutes: 6, status: .live), DepartureTime(minutes: 14, status: .scheduled)]
        ),
        Row(
            line: TransitLine(name: "M14A SBS", mode: .bus, color: .unknownLine),
            headsign: "Lower East Side",
            departures: [DepartureTime(minutes: 8, status: .live)]
        ),
    ]
}
