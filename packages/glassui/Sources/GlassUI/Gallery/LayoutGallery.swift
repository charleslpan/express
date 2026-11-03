#if DEBUG
    import SwiftUI

    /// The spacing scale as bars, the radii as tiles, and a concentric pair.
    struct LayoutGallery: View {
        @ScaledMetric private var labelWidth: CGFloat = 52
        @ScaledMetric private var tileSize: CGFloat = 64

        var body: some View {
            VStack(spacing: Spacing.md) {
                GalleryCard(title: "Spacing") {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        ForEach(Spacing.steps, id: \.name) { step in
                            AdaptiveRow {
                                TokenName(".\(step.name)")
                                    .frame(minWidth: labelWidth, alignment: .leading)
                                Capsule()
                                    .fill(.brand)
                                    .frame(width: step.value * 4, height: Spacing.xs)
                                Text("\(Int(step.value)) pt")
                                    .typography(.caption)
                                    .foregroundStyle(.textSecondary)
                                    .monospacedDigit()
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(step.name), \(Int(step.value)) points")
                        }
                    }
                }

                GalleryCard(title: "Radii") {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: tileSize), spacing: Spacing.sm, alignment: .top)],
                        alignment: .leading,
                        spacing: Spacing.md
                    ) {
                        ForEach(Radius.steps, id: \.name) { step in
                            VStack(spacing: Spacing.xs) {
                                Radius.shape(step.value)
                                    .fill(.surfaceRaised)
                                    .overlay(Radius.shape(step.value).strokeBorder(.brand, lineWidth: 1.5))
                                    .frame(width: tileSize, height: tileSize)
                                TokenName(".\(step.name)")
                                Text("\(Int(step.value)) pt")
                                    .typography(.caption)
                                    .foregroundStyle(.textSecondary)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(step.name), \(Int(step.value)) points")
                        }
                    }
                }

                GalleryCard(title: "Concentric") {
                    concentricDemo
                }
            }
        }

        /// A panel with `.xl` corners holding a card inset by `.xs`, whose corners `ConcentricRectangle` works out.
        private var concentricDemo: some View {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Inner card")
                        .typography(.cardTitle)
                    TokenName("ConcentricRectangle()")
                }
                .padding(Spacing.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.surface, in: ConcentricRectangle())
                .padding(Spacing.xs)
                .background(.brand.opacity(0.18), in: Radius.shape(Radius.xl))
                .containerShape(Radius.shape(Radius.xl))
                Text("Panel .xl (\(Int(Radius.xl)) pt), inset .xs: inner radius "
                    + "\(Int(Radius.concentric(outer: Radius.xl, inset: Spacing.xs))) pt.")
                    .typography(.caption)
                    .foregroundStyle(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }
#endif
