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

    /// Lays its subviews out left to right, wrapping onto a new line where the next one doesn't fit.
    private struct FlowLayout: Layout {
        var spacing: CGFloat

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
            let rows = rows(for: subviews, width: proposal.width ?? .infinity)
            let width = rows.map(\.width).max() ?? 0
            let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
            return CGSize(width: width, height: height)
        }

        func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
            var y = bounds.minY
            for row in rows(for: subviews, width: bounds.width) {
                var x = bounds.minX
                for index in row.indices {
                    let size = subviews[index].sizeThatFits(.unspecified)
                    subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                    x += size.width + spacing
                }
                y += row.height + spacing
            }
        }

        private struct Row {
            var indices: [Int] = []
            var width: CGFloat = 0
            var height: CGFloat = 0
        }

        private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
            var rows: [Row] = []
            var row = Row()
            for index in subviews.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
                if needed > width, !row.indices.isEmpty {
                    rows.append(row)
                    row = Row()
                }
                row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
                row.height = max(row.height, size.height)
                row.indices.append(index)
            }
            if !row.indices.isEmpty {
                rows.append(row)
            }
            return rows
        }
    }
#endif
