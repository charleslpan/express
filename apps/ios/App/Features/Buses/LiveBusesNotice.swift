import GlassUI
import SwiftUI

/// A calm note over the map, shown while bus positions may not be real time: Bus Time's feed, or the app's last
/// fetch of it, is more than a minute old, as the MTA's terms ask apps to say. It matches ``LiveTrainsNotice``, and
/// says so for trains too where both are stale, so the map never stacks two notes. It wraps at large text sizes rather
/// than truncating, and spans the width it's given.
struct LiveBusesNotice: View {
    /// Whether train positions may not be real time either.
    var includesTrains = false

    @ScaledMetric(relativeTo: .subheadline) private var gap = Spacing.xs

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: gap) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .foregroundStyle(.textSecondary)
            Text(message)
                .foregroundStyle(.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .typography(.secondary)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(in: Radius.shape(Radius.lg))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(message)
        .accessibilityIdentifier("buses.notice")
    }

    private var message: LocalizedStringKey {
        includesTrains
            ? "Bus and train positions may not be real time. Train positions are estimates."
            : "Bus positions may not be real time."
    }
}

#Preview("Bus positions notice") {
    VStack(spacing: Spacing.md) {
        LiveBusesNotice()
        LiveBusesNotice(includesTrains: true)
        LiveBusesNotice()
            .dynamicTypeSize(.accessibility5)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(LinearGradient(colors: [.green, .blue], startPoint: .top, endPoint: .bottom))
}
