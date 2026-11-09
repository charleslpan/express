import GlassUI
import SwiftUI

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
