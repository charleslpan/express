#if DEBUG
    import SwiftUI

    /// Each travel mode's accent and symbol, as an icon tile and a chip.
    struct ModesGallery: View {
        @ScaledMetric(relativeTo: .headline) private var tileSize: CGFloat = 40

        var body: some View {
            VStack(spacing: Spacing.md) {
                GalleryCard(title: "Accents") {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(TravelMode.allCases) { mode in
                            row(mode)
                            if mode != TravelMode.allCases.last {
                                Divider().padding(.leading, tileSize + Spacing.sm)
                            }
                        }
                    }
                }
                GalleryCard(title: "Chips") {
                    FlowChips()
                }
            }
        }

        private func row(_ mode: TravelMode) -> some View {
            AdaptiveRow {
                Image(systemName: mode.symbolName)
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(mode.onColor)
                    .frame(width: tileSize, height: tileSize)
                    .background(mode.color, in: Radius.shape(Radius.sm))
                VStack(alignment: .leading, spacing: Spacing.xxxs) {
                    Text(mode.title)
                        .typography(.cardTitle)
                    TokenName("TravelMode.\(mode)")
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, Spacing.xs)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(mode.title)
        }
    }

    /// Every mode as a capsule chip, wrapping onto as many lines as the text size needs.
    private struct FlowChips: View {
        var body: some View {
            FlowLayout(spacing: Spacing.xs) {
                ForEach(TravelMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbolName)
                        .typography(.badge)
                        .foregroundStyle(mode.onColor)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .background(mode.color, in: Capsule())
                }
            }
        }
    }
#endif
