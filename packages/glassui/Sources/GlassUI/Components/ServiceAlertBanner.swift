import SwiftUI

/// A service alert's short header under a departure row or in a list, such as "[L] trains are running with delays",
/// in its level's colour and icon: red for suspensions and skipped stops, amber for delays and reroutes, neutral for
/// every other notice. It's drawn without glass, as a tinted fill, so it can sit inside a sheet's glass.
///
/// ```swift
/// Button { showAlert() } label: {
///     ServiceAlertBanner(level: .severe, header: "No [6] trains between 3 Av-138 St and Pelham Bay Park")
/// }
/// .buttonStyle(.plain)
/// ```
///
/// Put it in a `Button` that opens the alert's full text; it shows a chevron to say so. VoiceOver reads it as one
/// element, such as "Suspended or stops skipped: No 6 trains between…".
public struct ServiceAlertBanner: View {
    /// How much an alert matters, which sets its colour and icon.
    public enum Level: Int, Hashable, Sendable, CaseIterable, Comparable {
        /// Any other notice, such as a moved stop: neutral.
        case info
        /// Delays, reroutes, and reduced service: amber.
        case warning
        /// Suspensions and skipped stops: red.
        case severe

        /// The colour of its icon and fill.
        public var color: Color {
            switch self {
            case .info: .statusInfo
            case .warning: .statusDelayed
            case .severe: .statusDisrupted
            }
        }

        /// Its SF Symbol.
        public var systemImage: String {
            switch self {
            case .info: "info.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .severe: "exclamationmark.octagon.fill"
            }
        }

        /// What VoiceOver says before the header.
        public var accessibilityName: String {
            switch self {
            case .info: "Service notice"
            case .warning: "Delays or changes"
            case .severe: "Suspended or stops skipped"
            }
        }

        public static func < (lhs: Level, rhs: Level) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    private let level: Level
    private let header: String
    private let lineLimit: Int?
    private let showsChevron: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var gap = Spacing.xs

    /// A banner for an alert at `level` with `header`, as the MTA wrote it. `lineLimit` caps the header (no cap at
    /// accessibility text sizes); `showsChevron` says it opens the full text.
    public init(level: Level, header: String, lineLimit: Int? = 2, showsChevron: Bool = true) {
        self.level = level
        self.header = header
        self.lineLimit = lineLimit
        self.showsChevron = showsChevron
    }

    public var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // The icon and chevron go above the header, so it has the whole width to wrap in.
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack {
                        icon
                        Spacer(minLength: 0)
                        chevron
                    }
                    text
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: gap) {
                    icon
                    text
                    chevron
                }
            }
        }
        .typography(.secondary)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .frame(minHeight: 44)
        .background(fill, in: Radius.shape(Radius.sm))
        .contentShape(Radius.shape(Radius.sm))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(level.accessibilityName): \(header)")
    }

    private var icon: some View {
        Image(systemName: level.systemImage)
            .foregroundStyle(level.color)
    }

    private var text: some View {
        Text(header)
            .foregroundStyle(.textPrimary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : lineLimit)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var chevron: some View {
        if showsChevron {
            Image(systemName: "chevron.right")
                .typography(.captionEmphasized)
                .foregroundStyle(.textTertiary)
        }
    }

    /// A light wash of the level's colour, a little stronger where Reduce Transparency asks for more contrast.
    private var fill: Color {
        level.color.opacity(reduceTransparency ? 0.22 : 0.14)
    }
}

#if DEBUG
    #Preview("Service alert banners") {
        VStack(spacing: Spacing.sm) {
            ServiceAlertBanner(level: .severe, header: "No [6] trains between 3 Av-138 St and Pelham Bay Park")
            ServiceAlertBanner(level: .warning, header: "[L] trains are running with delays")
            ServiceAlertBanner(level: .info, header: "Enter 5 Av/53 St [E][F] Station at 5 Av only")
        }
        .padding()
    }
#endif
