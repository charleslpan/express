import GlassUI
import SwiftUI

// What the home sheet's slots show until the features that fill them land. Each feature replaces its placeholder
// in `HomeSheetContent`'s convenience initializer with its own view.

/// Stands in for the service alert chip (A3): a quiet chip that claims nothing about the service.
struct AlertChipPlaceholder: View {
    var body: some View {
        Label("Service alerts", systemImage: "exclamationmark.bubble")
            .typography(.captionEmphasized)
            .foregroundStyle(.textSecondary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(.fill.tertiary, in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Service alerts will show here")
    }
}

/// A section's heading in the home sheet, such as "Nearby".
struct HomeSectionHeading: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .typography(.sectionTitle)
            .foregroundStyle(.textPrimary)
            .accessibilityAddTraits(.isHeader)
    }
}
