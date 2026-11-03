#if DEBUG
    import SwiftUI

    /// The semantic colors, as swatches grouped by role.
    struct ColorsGallery: View {
        private struct Swatch: Identifiable {
            var name: String
            var role: String
            var color: Color
            var id: String {
                name
            }
        }

        private static let groups: [(title: String, swatches: [Swatch])] = [
            ("Backgrounds", [
                Swatch(name: "canvas", role: "Screen base", color: .canvas),
                Swatch(name: "canvasGrouped", role: "Grouped screen", color: .canvasGrouped),
                Swatch(name: "surface", role: "Card or row", color: .surface),
                Swatch(name: "surfaceRaised", role: "On a card", color: .surfaceRaised),
            ]),
            ("Text", [
                Swatch(name: "textPrimary", role: "Titles, body", color: .textPrimary),
                Swatch(name: "textSecondary", role: "Supporting", color: .textSecondary),
                Swatch(name: "textTertiary", role: "Placeholder", color: .textTertiary),
                Swatch(name: "separatorLine", role: "Hairlines", color: .separatorLine),
            ]),
            ("Brand and status", [
                Swatch(name: "brand", role: "Accent, actions", color: .brand),
                Swatch(name: "statusOnTime", role: "On time, live", color: .statusOnTime),
                Swatch(name: "statusDelayed", role: "Delays", color: .statusDelayed),
                Swatch(name: "statusDisrupted", role: "Suspended", color: .statusDisrupted),
                Swatch(name: "statusInfo", role: "Information", color: .statusInfo),
            ]),
        ]

        @ScaledMetric private var swatchWidth: CGFloat = 150

        var body: some View {
            VStack(spacing: Spacing.md) {
                ForEach(Self.groups, id: \.title) { group in
                    GalleryCard(title: group.title) {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: swatchWidth), spacing: Spacing.sm, alignment: .top)],
                            alignment: .leading,
                            spacing: Spacing.md
                        ) {
                            ForEach(group.swatches) { swatch in
                                swatchView(swatch)
                            }
                        }
                    }
                }
            }
        }

        private func swatchView(_ swatch: Swatch) -> some View {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Radius.shape(Radius.sm)
                    .fill(swatch.color)
                    .overlay(Radius.shape(Radius.sm).strokeBorder(.separatorLine, lineWidth: 0.5))
                    .frame(height: 52)
                VStack(alignment: .leading, spacing: Spacing.xxxs) {
                    Text(swatch.role)
                        .typography(.captionEmphasized)
                        .foregroundStyle(.textPrimary)
                    TokenName(".\(swatch.name)")
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(swatch.name), \(swatch.role)")
        }
    }
#endif
