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

/// Stands in for Home and Work (P2): the two chips, side by side where they fit and stacked where they don't.
struct SavedPlacesPlaceholder: View {
    var body: some View {
        AdaptiveStack(spacing: Spacing.xs) {
            chip("Home", systemImage: "house.fill")
            chip("Work", systemImage: "briefcase.fill")
        }
    }

    private func chip(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Button {
            // Saved places (P2) sets and opens these.
        } label: {
            Label(title, systemImage: systemImage)
                .typography(.button)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .accessibilityHint("Saving places is coming soon")
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

/// Stands in for the Nearby section (N1): its heading over departure rows in their loading state.
struct NearbySectionPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HomeSectionHeading("Nearby")
            VStack(spacing: 0) {
                ForEach(Self.rows, id: \.line.id) { row in
                    DepartureRow(line: row.line, headsign: row.headsign, departures: row.departures)
                    Divider()
                }
            }
            .redacted(reason: .placeholder)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Departures near you will show here")
        }
    }

    private struct Row {
        var line: TransitLine
        var headsign: String
        var departures: [DepartureTime]
    }

    /// Plausible rows to draw redacted, so the placeholder has a departure list's shape.
    private static let rows = [
        Row(
            line: TransitLine(name: "L", mode: .subway, color: LineColor(hex: "A7A9AC") ?? .black, textColor: .white),
            headsign: "8 Av",
            departures: [DepartureTime(minutes: 3, status: .live), DepartureTime(minutes: 9, status: .scheduled)]
        ),
        Row(
            line: TransitLine(name: "M14A SBS", mode: .bus, color: LineColor(hex: "2850AD") ?? .black),
            headsign: "Lower East Side",
            departures: [DepartureTime(minutes: 6, status: .live), DepartureTime(minutes: 14, status: .scheduled)]
        ),
    ]
}

/// Stands in for the Saved section (P2): its heading and a note on what it will hold.
struct SavedSectionPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HomeSectionHeading("Saved")
            Text("Places and lines you save will show here.")
                .typography(.secondary)
                .foregroundStyle(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
