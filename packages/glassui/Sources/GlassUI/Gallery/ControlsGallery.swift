#if DEBUG
    import SwiftUI

    /// The glass controls as a map screen floats them: search at the top, buttons at the side, a card and its
    /// actions at the bottom.
    struct ControlsGallery: View {
        @State private var query = ""
        @Namespace private var glass

        var body: some View {
            MapStage {
                VStack(spacing: Spacing.floatingInset) {
                    GlassSearchField("Search for a place or address", text: $query) {
                        AccountBadge()
                    }
                    HStack {
                        Spacer(minLength: 0)
                        GlassEffectContainer(spacing: Spacing.floatingInset) {
                            VStack(spacing: Spacing.floatingInset) {
                                GlassIconButton("Show my location", systemImage: "location.fill") {}
                                    .glassEffectID("location", in: glass)
                                GlassIconButton("Map layers", systemImage: "square.3.layers.3d") {}
                                    .glassEffectID("layers", in: glass)
                            }
                        }
                    }
                    Spacer(minLength: Spacing.xl)
                    GlassCard(action: {}) {
                        Text(verbatim: "14 St–Union Sq")
                            .typography(.cardTitle)
                        Text(verbatim: "4 5 6 L N Q R W · 2 min walk")
                            .typography(.secondary)
                            .foregroundStyle(.textSecondary)
                    }
                    ActionRow()
                }
            }
        }
    }

    /// Every state of each control: empty and filled search, standard, prominent, and disabled buttons.
    struct ControlStatesGallery: View {
        @State private var empty = ""
        @State private var filled = "Union Sq"

        var body: some View {
            VStack(spacing: Spacing.md) {
                GalleryCard(title: "Search field") {
                    MapStage {
                        VStack(spacing: Spacing.floatingInset) {
                            GlassSearchField("Search for a place or address", text: $empty)
                            GlassSearchField("Search for a place or address", text: $filled)
                        }
                    }
                }
                GalleryCard(title: "Buttons") {
                    MapStage {
                        VStack(alignment: .leading, spacing: Spacing.floatingInset) {
                            ActionRow()
                            GlassButton("Unavailable") {}
                                .disabled(true)
                            GlassEffectContainer(spacing: Spacing.floatingInset) {
                                HStack(spacing: Spacing.floatingInset) {
                                    GlassIconButton("Close", systemImage: "xmark") {}
                                    GlassIconButton("Share", systemImage: "square.and.arrow.up") {}
                                    GlassIconButton("Start", systemImage: "play.fill", prominence: .prominent) {}
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    /// The opaque fallback for Reduce Transparency, and the borders Increase Contrast adds, forced on.
    struct ControlFallbacksGallery: View {
        var body: some View {
            VStack(spacing: Spacing.md) {
                GalleryCard(title: "Reduce Transparency") {
                    FallbackStage()
                        .environment(\.forcesOpaqueGlass, true)
                }
                GalleryCard(title: "Increase Contrast") {
                    FallbackStage()
                        .environment(\.forcesHighContrastGlass, true)
                }
            }
        }
    }

    // MARK: - Building blocks

    /// A compact set of controls over the map, for comparing the fallbacks.
    private struct FallbackStage: View {
        @State private var query = ""

        var body: some View {
            MapStage {
                VStack(alignment: .leading, spacing: Spacing.floatingInset) {
                    GlassSearchField("Search for a place or address", text: $query)
                    GlassCard {
                        Text(verbatim: "Grand Central–42 St")
                            .typography(.cardTitle)
                        Text(verbatim: "4 5 6 7 S · 4 min walk")
                            .typography(.secondary)
                            .foregroundStyle(.textSecondary)
                    }
                    HStack(spacing: Spacing.floatingInset) {
                        GlassIconButton("Show my location", systemImage: "location.fill") {}
                        ActionRow()
                    }
                }
            }
        }
    }

    /// A card's actions: the primary one tinted, side by side, or stacked at accessibility text sizes.
    private struct ActionRow: View {
        var body: some View {
            GlassEffectContainer(spacing: Spacing.floatingInset) {
                AdaptiveRow(spacing: Spacing.floatingInset) {
                    GlassButton(
                        "Directions",
                        systemImage: "arrow.triangle.turn.up.right.diamond.fill",
                        prominence: .prominent
                    ) {}
                    GlassButton("Save", systemImage: "bookmark") {}
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// An account button for the search field's accessory: plain, since it sits inside the field's glass.
    private struct AccountBadge: View {
        var body: some View {
            Button {} label: {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.textSecondary)
                    .frame(minWidth: GlassMetrics.minimumTarget, minHeight: GlassMetrics.minimumTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Account")
        }
    }

    /// Floats `content` over a stand-in map, so the glass has something to refract.
    struct MapStage<Content: View>: View {
        @ViewBuilder var content: Content

        var body: some View {
            content
                .padding(Spacing.floatingInset)
                .frame(maxWidth: .infinity)
                .background { MapBackdrop() }
                .clipShape(Radius.shape(Radius.lg))
        }
    }

    /// A drawn stand-in for the Google map: land, a park, a river, Manhattan's tilted street grid, and a subway line.
    /// Its colours are literals on purpose: it imitates the map's style, which isn't a GlassUI token.
    struct MapBackdrop: View {
        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            let dark = colorScheme == .dark
            let land = dark ? Color(red: 0.13, green: 0.14, blue: 0.16) : Color(red: 0.95, green: 0.94, blue: 0.91)
            let park = dark ? Color(red: 0.12, green: 0.22, blue: 0.15) : Color(red: 0.78, green: 0.90, blue: 0.74)
            let water = dark ? Color(red: 0.09, green: 0.16, blue: 0.26) : Color(red: 0.67, green: 0.82, blue: 0.95)
            let street = dark ? Color(red: 0.24, green: 0.26, blue: 0.30) : Color.white
            let line = Color(red: 0.0, green: 0.58, blue: 0.24)

            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(land))

                var river = Path()
                river.move(to: CGPoint(x: 0, y: 0))
                river.addLine(to: CGPoint(x: size.width * 0.16, y: 0))
                river.addCurve(
                    to: CGPoint(x: size.width * 0.1, y: size.height),
                    control1: CGPoint(x: size.width * 0.26, y: size.height * 0.4),
                    control2: CGPoint(x: size.width * 0.02, y: size.height * 0.6)
                )
                river.addLine(to: CGPoint(x: 0, y: size.height))
                river.closeSubpath()
                context.fill(river, with: .color(water))

                // The grid runs about 29° off north, like Manhattan's.
                var grid = context
                grid.translateBy(x: size.width / 2, y: size.height / 2)
                grid.rotate(by: .degrees(29))
                let reach = max(size.width, size.height)
                let parkRect = CGRect(x: 40, y: -reach * 0.35, width: 110, height: reach * 0.3)
                grid.fill(Path(roundedRect: parkRect, cornerRadius: 4), with: .color(park))
                for offset in stride(from: -reach, through: reach, by: 22) {
                    var path = Path()
                    path.move(to: CGPoint(x: -reach, y: offset))
                    path.addLine(to: CGPoint(x: reach, y: offset))
                    grid.stroke(path, with: .color(street), lineWidth: 2)
                }
                for offset in stride(from: -reach, through: reach, by: 64) {
                    var path = Path()
                    path.move(to: CGPoint(x: offset, y: -reach))
                    path.addLine(to: CGPoint(x: offset, y: reach))
                    grid.stroke(path, with: .color(street), lineWidth: 5)
                }

                var subway = Path()
                let stops = [
                    CGPoint(x: size.width * 0.45, y: size.height * 0.55),
                    CGPoint(x: size.width * 0.58, y: size.height * 0.26),
                ]
                subway.move(to: CGPoint(x: size.width * 0.3, y: size.height))
                subway.addLine(to: stops[0])
                subway.addLine(to: CGPoint(x: size.width * 0.7, y: 0))
                context.stroke(subway, with: .color(line), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                for stop in stops {
                    let dot = Path(ellipseIn: CGRect(x: stop.x - 5, y: stop.y - 5, width: 10, height: 10))
                    context.fill(dot, with: .color(.white))
                    context.stroke(dot, with: .color(line), lineWidth: 2.5)
                }
            }
            .accessibilityHidden(true)
        }
    }

    // MARK: - Previews

    /// Glass icon buttons that morph into and out of each other as the extra ones come and go.
    private struct MorphingDemo: View {
        @State private var isExpanded = false
        @Namespace private var glass

        var body: some View {
            GlassEffectContainer(spacing: Spacing.floatingInset) {
                VStack(spacing: Spacing.floatingInset) {
                    GlassIconButton(
                        isExpanded ? "Fewer controls" : "More controls",
                        systemImage: isExpanded ? "xmark" : "ellipsis"
                    ) {
                        withAnimation(.bouncy) { isExpanded.toggle() }
                    }
                    .glassEffectID("toggle", in: glass)
                    if isExpanded {
                        GlassIconButton("Show my location", systemImage: "location.fill") {}
                            .glassEffectID("location", in: glass)
                        GlassIconButton("Map layers", systemImage: "square.3.layers.3d") {}
                            .glassEffectID("layers", in: glass)
                    }
                }
            }
        }
    }

    #Preview("Controls") {
        GlassUIGallery(sections: [.controls, .controlStates, .controlFallbacks])
    }

    #Preview("Controls, dark, AX5") {
        GlassUIGallery(sections: [.controls])
            .preferredColorScheme(.dark)
            .dynamicTypeSize(.accessibility5)
    }

    #Preview("Controls, Reduce Transparency") {
        GlassUIGallery(sections: [.controls])
            .environment(\.forcesOpaqueGlass, true)
    }

    #Preview("Morphing") {
        MapStage {
            MorphingDemo()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .padding()
    }
#endif
