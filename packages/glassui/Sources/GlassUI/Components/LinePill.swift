import SwiftUI

/// A line's badge in the MTA's style: a round bullet in the line's colour for subway services (the 1, A, L), a
/// diamond for express variants (the <6>, <7>), and a rounded rectangle that fits the name for buses and the
/// Staten Island Railway (M15, B44 SBS, SIR). It scales with Dynamic Type.
///
/// ```swift
/// LinePill(line)                    // in a departure row
/// LinePill(line, size: .compact)    // on a journey's segment bar
/// ```
///
/// The pill is decoration for VoiceOver by default: its label is the line's spoken name, such as "6 express train",
/// and a row that holds it usually speaks it as part of its own label.
public struct LinePill: View {
    /// How big the badge is drawn.
    public enum Size: Sendable {
        /// Beside a headsign, in a row or a card.
        case regular
        /// Inside something small, such as a journey's segment bar.
        case compact
    }

    private let line: TransitLine
    private let size: Size
    @ScaledMetric(relativeTo: .subheadline) private var regularHeight: CGFloat = 26
    @ScaledMetric(relativeTo: .caption) private var compactHeight: CGFloat = 20

    public init(_ line: TransitLine, size: Size = .regular) {
        self.line = line
        self.size = size
    }

    private var height: CGFloat {
        size == .regular ? regularHeight : compactHeight
    }

    public var body: some View {
        let style = line.badgeStyle
        Group {
            switch style {
            case .bullet:
                label.frame(width: height, height: height)
            case .diamond:
                // Wider and taller than a bullet, so the name clears the slanted edges.
                label.frame(width: height * 1.3, height: height * 1.3)
            case .pill:
                label
                    .fixedSize()
                    .padding(.horizontal, height * 0.3)
                    .frame(minWidth: height * 1.4)
                    .frame(height: height)
            }
        }
        .background(line.color.color, in: LineBadgeShape(style: style))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.accessibilityName)
    }

    private var label: some View {
        Text(line.name)
            .font(size == .regular ? Typography.badge.font : .system(.caption, design: .rounded, weight: .bold))
            .foregroundStyle(line.resolvedTextColor.color)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

/// The outline of a line badge: a circle, a diamond, or a rounded rectangle, by ``TransitLine/BadgeStyle``.
public struct LineBadgeShape: Shape {
    public var style: TransitLine.BadgeStyle

    public init(style: TransitLine.BadgeStyle) {
        self.style = style
    }

    public func path(in rect: CGRect) -> Path {
        switch style {
        case .bullet:
            return Circle().path(in: rect)
        case .diamond:
            // Slightly rounded points, as on the MTA's signs.
            let corner = min(rect.width, rect.height) * 0.08
            let points = [
                CGPoint(x: rect.midX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.midY),
                CGPoint(x: rect.midX, y: rect.maxY),
                CGPoint(x: rect.minX, y: rect.midY),
            ]
            var path = Path()
            path.move(to: CGPoint(x: (points[3].x + points[0].x) / 2, y: (points[3].y + points[0].y) / 2))
            for index in points.indices {
                let next = points[(index + 1) % points.count]
                path.addArc(tangent1End: points[index], tangent2End: next, radius: corner)
            }
            path.closeSubpath()
            return path
        case .pill:
            return Radius.shape(min(rect.height * 0.28, Radius.xs)).path(in: rect)
        }
    }
}

#if DEBUG
    private struct LinePillPreview: View {
        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.xs) {
                    ForEach(TransitLine.samples) { LinePill($0) }
                }
                HStack(spacing: Spacing.xxs) {
                    ForEach(TransitLine.samples) { LinePill($0, size: .compact) }
                }
            }
            .padding()
        }
    }

    #Preview("LinePill") {
        LinePillPreview()
    }

    #Preview("LinePill, dark") {
        LinePillPreview()
            .preferredColorScheme(.dark)
    }

    #Preview("LinePill, AX5") {
        ScrollView(.horizontal) {
            LinePillPreview()
        }
        .dynamicTypeSize(.accessibility5)
    }
#endif
