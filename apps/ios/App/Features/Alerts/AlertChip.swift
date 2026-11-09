import GlassUI
import SwiftUI
import TransitKit

/// The home sheet's alert chip: a summary of the alerts that apply now to the lines on the Nearby board, such as
/// "2 lines with alerts" in the colour of the worst, with their bullets. "Good service near you" when there are
/// none, and "Line status" until the board has loaded. Tapping it opens line status
/// (``AppRouter/showLineStatus(nearbyBuses:)``).
///
/// It's a filled capsule rather than glass, since it sits inside the sheet's glass.
struct AlertChip: View {
    let model: NearbyModel
    @Environment(AppRouter.self) private var router
    @ScaledMetric(relativeTo: .subheadline) private var gap = Spacing.xs

    /// How many affected lines' bullets the chip shows.
    static let bulletCount = 3

    var body: some View {
        Button {
            router.showLineStatus(nearbyBuses: board?.busLines() ?? [])
        } label: {
            AdaptiveStack(spacing: gap) {
                Label {
                    Text(title)
                        .foregroundStyle(.textPrimary)
                        .multilineTextAlignment(.leading)
                } icon: {
                    Image(systemName: systemImage)
                        .foregroundStyle(iconColor)
                }
                .typography(.button)
                if !affected.isEmpty {
                    HStack(spacing: Spacing.xxs) {
                        ForEach(affected.prefix(Self.bulletCount)) { line in
                            LinePill(
                                TransitLine(LineStatusLine(id: line.id, bullet: line.bullet, name: nil)),
                                size: .compact
                            )
                        }
                    }
                }
                Image(systemName: "chevron.right")
                    .typography(.captionEmphasized)
                    .foregroundStyle(.textTertiary)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
            .frame(minHeight: 44)
            .background(.fill.tertiary, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens the status of every subway line and the buses near you.")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("alerts.chip")
    }

    private var board: NearbyBoard? {
        if case let .loaded(board) = model.content {
            board
        } else {
            nil
        }
    }

    /// The board's lines with alerts that apply now, the most severe first.
    private var affected: [LineAlertSummary] {
        board?.linesWithAlerts() ?? []
    }

    private var title: String {
        guard board != nil else { return "Line status" }
        switch affected.count {
        case 0: return "Good service near you"
        case 1: return "1 line with alerts"
        default: return "\(affected.count) lines with alerts"
        }
    }

    private var level: ServiceAlertBanner.Level? {
        affected.map(\.level).max().map { ServiceAlertBanner.Level($0) }
    }

    private var systemImage: String {
        if let level {
            return level.systemImage
        }
        return board == nil ? "list.bullet" : "checkmark.circle.fill"
    }

    private var iconColor: Color {
        if let level {
            return level.color
        }
        return board == nil ? .textSecondary : .statusOnTime
    }

    private var accessibilityLabel: String {
        let names = affected
            .map { TransitLine(LineStatusLine(id: $0.id, bullet: $0.bullet, name: nil)).accessibilityName }
        return names.isEmpty ? title : "\(title): \(names.formatted(.list(type: .and)))"
    }
}
