import SwiftUI

/// One leg of a journey, as plain values: what ``JourneySegmentBar`` draws.
public struct JourneyLeg: Hashable, Sendable, Identifiable {
    /// How the leg is travelled.
    public enum Kind: Hashable, Sendable {
        case walk
        case ride(TransitLine)
    }

    public var id: String
    public var kind: Kind
    /// How long the leg takes, in minutes.
    public var minutes: Int

    public init(id: String? = nil, _ kind: Kind, minutes: Int) {
        self.kind = kind
        self.minutes = max(minutes, 0)
        self.id = id ?? {
            switch kind {
            case .walk: "walk-\(minutes)"
            case let .ride(line): "\(line.id)-\(minutes)"
            }
        }()
    }

    /// A walking leg.
    public static func walk(minutes: Int) -> JourneyLeg {
        JourneyLeg(.walk, minutes: minutes)
    }

    /// A leg on `line`.
    public static func ride(_ line: TransitLine, minutes: Int) -> JourneyLeg {
        JourneyLeg(.ride(line), minutes: minutes)
    }

    /// What VoiceOver says: "Walk, 4 minutes" or "6 express train, 12 minutes".
    public var accessibilityLabel: String {
        let name = switch kind {
        case .walk: String(localized: "Walk")
        case let .ride(line): line.accessibilityName
        }
        return String(localized: "\(name), \(minutes) minutes")
    }
}

/// A journey at a glance: one segment per leg, each as long as the leg takes, walks as grey dots and rides in the
/// line's colour with its pill. Short legs keep enough room for their pill; the rest share what's left.
///
/// ```swift
/// JourneySegmentBar(legs: [.walk(minutes: 4), .ride(sixExpress, minutes: 12), .walk(minutes: 3)])
/// ```
///
/// VoiceOver reads the legs in order, as one element.
public struct JourneySegmentBar: View {
    private let legs: [JourneyLeg]
    @ScaledMetric(relativeTo: .caption) private var barHeight: CGFloat = 24
    @ScaledMetric(relativeTo: .caption) private var dotSize: CGFloat = 5

    public init(legs: [JourneyLeg]) {
        self.legs = legs
    }

    public var body: some View {
        SegmentLayout(spacing: Spacing.xxs) {
            ForEach(legs.indices, id: \.self) { index in
                let leg = legs[index]
                segment(for: leg)
                    .layoutValue(key: LegWeight.self, value: Double(max(leg.minutes, 1)))
                    // Walks may get narrow; a ride keeps room for its pill.
                    .layoutValue(key: LegMinimumWidth.self, value: leg.kind == .walk ? barHeight * 0.75 : nil)
            }
        }
        .frame(minHeight: barHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(legs.map(\.accessibilityLabel).joined(separator: String(localized: ", then ")))
    }

    @ViewBuilder
    private func segment(for leg: JourneyLeg) -> some View {
        switch leg.kind {
        case .walk:
            WalkDots(dotSize: dotSize)
                .foregroundStyle(TravelMode.walk.color)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .ride(line):
            LinePill(line, size: .compact)
                // A hairline in the text colour sets the pill apart from the segment it sits on.
                .overlay(LineBadgeShape(style: line.badgeStyle).stroke(line.resolvedTextColor.color, lineWidth: 1.5))
                .padding(Spacing.xxxs)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(line.color.color, in: Capsule())
        }
    }

    /// The width of each segment: shares of `available` in proportion to `weights`, except that none is narrower
    /// than its entry in `minimums`. Where even the minimums don't fit, they shrink together.
    static func widths(weights: [Double], minimums: [CGFloat], available: CGFloat) -> [CGFloat] {
        let count = min(weights.count, minimums.count)
        guard count > 0 else {
            return []
        }
        let available = max(available, 0)
        let totalMinimum = minimums.prefix(count).reduce(0, +)
        if totalMinimum >= available {
            let scale = totalMinimum > 0 ? available / totalMinimum : 0
            return minimums.prefix(count).map { $0 * scale }
        }

        var widths = [CGFloat](repeating: 0, count: count)
        var pinned = [Bool](repeating: false, count: count)
        while true {
            let free = (0 ..< count).filter { !pinned[$0] }
            let freeWeight = free.map { max(weights[$0], 0) }.reduce(0, +)
            let freeSpace = available - (0 ..< count).filter { pinned[$0] }.map { widths[$0] }.reduce(0, +)
            func share(_ index: Int) -> CGFloat {
                freeWeight > 0
                    ? freeSpace * CGFloat(max(weights[index], 0) / freeWeight)
                    : freeSpace / CGFloat(free.count)
            }
            // Pin every segment whose share falls short of its minimum, then share out what's left again.
            let short = free.filter { share($0) < minimums[$0] }
            if short.isEmpty {
                for index in free {
                    widths[index] = share(index)
                }
                return widths
            }
            for index in short {
                pinned[index] = true
                widths[index] = minimums[index]
            }
        }
    }
}

/// How long a leg takes, which sets its share of the bar.
private struct LegWeight: LayoutValueKey {
    static let defaultValue: Double = 1
}

/// The narrowest a leg may be drawn; `nil` for its ideal width (a ride's pill).
private struct LegMinimumWidth: LayoutValueKey {
    static let defaultValue: CGFloat? = nil
}

/// Lays legs out side by side across the full width, as wide as ``JourneySegmentBar/widths(weights:minimums:available:)``
/// says, all as tall as the tallest.
private struct SegmentLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        let gaps = spacing * CGFloat(max(subviews.count - 1, 0))
        let width = proposal.width ?? (minimums(subviews).reduce(0, +) + gaps)
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let gaps = spacing * CGFloat(max(subviews.count - 1, 0))
        let widths = JourneySegmentBar.widths(
            weights: subviews.map { $0[LegWeight.self] },
            minimums: minimums(subviews),
            available: bounds.width - gaps
        )
        var x = bounds.minX
        for (subview, width) in zip(subviews, widths) {
            subview.place(
                at: CGPoint(x: x, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
            x += width + spacing
        }
    }

    private func minimums(_ subviews: Subviews) -> [CGFloat] {
        subviews.map { $0[LegMinimumWidth.self] ?? $0.sizeThatFits(.unspecified).width }
    }
}

/// A row of round dots along the middle of its frame: a walking leg.
private struct WalkDots: Shape {
    var dotSize: CGFloat

    func path(in rect: CGRect) -> Path {
        var line = Path()
        let inset = dotSize / 2
        line.move(to: CGPoint(x: rect.minX + inset, y: rect.midY))
        line.addLine(to: CGPoint(x: max(rect.maxX - inset, rect.minX + inset), y: rect.midY))
        // A zero-length dash with a round cap draws a dot.
        return line.strokedPath(StrokeStyle(lineWidth: dotSize, lineCap: .round, dash: [0, dotSize * 1.9]))
    }
}

#if DEBUG
    private struct JourneySegmentBarPreview: View {
        var body: some View {
            VStack(spacing: Spacing.md) {
                ForEach(JourneyLeg.sampleJourneys.indices, id: \.self) { index in
                    JourneySegmentBar(legs: JourneyLeg.sampleJourneys[index])
                }
            }
            .padding()
        }
    }

    #Preview("JourneySegmentBar") {
        JourneySegmentBarPreview()
    }

    #Preview("JourneySegmentBar, dark") {
        JourneySegmentBarPreview()
            .preferredColorScheme(.dark)
    }

    #Preview("JourneySegmentBar, AX5") {
        JourneySegmentBarPreview()
            .dynamicTypeSize(.accessibility5)
    }
#endif
