import GlassUI
import SwiftUI

/// A calm note over the map, shown while train positions may not be real time: the subway's live data, or the app's
/// last fetch of it, is more than a minute old. The MTA's terms ask apps to say so; positions are estimates anyway.
/// It wraps at large text sizes rather than truncating, and spans the width it's given.
struct LiveTrainsNotice: View {
    @ScaledMetric(relativeTo: .subheadline) private var gap = Spacing.xs

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: gap) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .foregroundStyle(.textSecondary)
            Text("Train positions are estimates and may not be real time.")
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
        .accessibilityLabel("Train positions are estimates and may not be real time.")
        .accessibilityIdentifier("trains.notice")
    }
}

#Preview("Train positions notice") {
    VStack(spacing: Spacing.md) {
        LiveTrainsNotice()
        LiveTrainsNotice()
            .dynamicTypeSize(.accessibility5)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(LinearGradient(colors: [.green, .blue], startPoint: .top, endPoint: .bottom))
}
