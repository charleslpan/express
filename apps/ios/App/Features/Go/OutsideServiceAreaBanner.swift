import GlassUI
import SwiftUI

/// A calm note over the map, shown while the user is outside the area Express serves (`ServiceArea.nyc`). It wraps
/// at large text sizes rather than truncating, and spans the width it's given.
struct OutsideServiceAreaBanner: View {
    @ScaledMetric(relativeTo: .subheadline) private var gap = Spacing.xs

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: gap) {
            Image(systemName: "map")
                .foregroundStyle(.textSecondary)
            Text("Express covers New York City for now.")
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
        .accessibilityLabel("Express covers New York City for now.")
        .accessibilityIdentifier("home.outside-service-area")
    }
}

#Preview("Outside NYC banner") {
    VStack(spacing: Spacing.md) {
        OutsideServiceAreaBanner()
        OutsideServiceAreaBanner()
            .dynamicTypeSize(.accessibility5)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(LinearGradient(colors: [.green, .blue], startPoint: .top, endPoint: .bottom))
}
