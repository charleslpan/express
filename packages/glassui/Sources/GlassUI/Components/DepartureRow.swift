import SwiftUI

/// A line's next departures from a stop: its pill, its headsign, and the next two or three times, the first one
/// loudest. At accessibility text sizes the times move under the headsign. VoiceOver reads it as one element, such
/// as "M15 Select Bus to South Ferry, 3 minutes, live, 11 minutes, scheduled".
///
/// ```swift
/// DepartureRow(line: m15, headsign: "South Ferry", departures: times)
/// ```
///
/// The row is at least 44 points tall, so it makes a full-size tap target inside a `Button` or `NavigationLink`.
public struct DepartureRow: View {
    private let line: TransitLine
    private let headsign: String
    private let detail: String?
    private let departures: [DepartureTime]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric private var gap = Spacing.sm

    /// A row for `line` towards `headsign`. `detail` is an optional second line, such as "Uptown · Platform 2";
    /// only the first three `departures` show.
    public init(line: TransitLine, headsign: String, detail: String? = nil, departures: [DepartureTime]) {
        self.line = line
        self.headsign = headsign
        self.detail = detail
        self.departures = Array(departures.prefix(3))
    }

    public var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    LinePill(line)
                    titles
                    times
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: gap) {
                    LinePill(line)
                    titles
                    Spacer(minLength: Spacing.xs)
                    times
                }
            }
        }
        .padding(.vertical, Spacing.xs)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: Spacing.xxxs) {
            Text(headsign)
                .typography(.cardTitle)
                .foregroundStyle(.textPrimary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            if let detail {
                Text(detail)
                    .typography(.secondary)
                    .foregroundStyle(.textSecondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            }
        }
    }

    @ViewBuilder
    private var times: some View {
        if departures.isEmpty {
            Text("No departures")
                .typography(.secondary)
                .foregroundStyle(.textSecondary)
        } else {
            // At accessibility sizes three times can outgrow the screen's width, so they wrap.
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(FlowLayout(spacing: Spacing.sm))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Spacing.sm))
            layout {
                ForEach(Array(departures.enumerated()), id: \.offset) { index, departure in
                    RealtimeBadge(departure, prominence: index == 0 ? .primary : .secondary)
                }
            }
        }
    }

    private var accessibilityLabel: String {
        let times = departures.isEmpty
            ? [String(localized: "no departures")]
            : departures.map(\.accessibilityLabel)
        return ([String(localized: "\(line.accessibilityName) to \(headsign)")] + times).joined(separator: ", ")
    }
}

#if DEBUG
    private struct DepartureRowPreview: View {
        var body: some View {
            VStack(spacing: 0) {
                ForEach(DepartureRow.samples.indices, id: \.self) { index in
                    DepartureRow.samples[index]
                    Divider()
                }
            }
            .padding(.horizontal)
        }
    }

    #Preview("DepartureRow") {
        DepartureRowPreview()
    }

    #Preview("DepartureRow, dark") {
        DepartureRowPreview()
            .preferredColorScheme(.dark)
    }

    #Preview("DepartureRow, AX5") {
        ScrollView {
            DepartureRowPreview()
        }
        .dynamicTypeSize(.accessibility5)
    }
#endif
