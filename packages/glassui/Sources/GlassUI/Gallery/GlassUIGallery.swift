#if DEBUG
    import SwiftUI

    /// A section of the ``GlassUIGallery``. Add a case (and its view in `GlassUIGallery.content(for:)`) for each
    /// group of components you add to GlassUI, and a harness screen for it in the app.
    public enum GallerySection: String, CaseIterable, Identifiable, Sendable {
        case colors
        case modes
        case typography
        case layout
        case lines
        case journeys
        case departures

        public var id: Self {
            self
        }

        var title: String {
            switch self {
            case .colors: "Colors"
            case .modes: "Modes"
            case .typography: "Typography"
            case .layout: "Spacing & Radii"
            case .lines: "Lines"
            case .journeys: "Journeys"
            case .departures: "Departures"
            }
        }

        var summary: String {
            switch self {
            case .colors: "Semantic colors, by role. Each adapts to light, dark, and Increase Contrast."
            case .modes: "Accent and symbol per way of travel. Line colors come from the feed, not from here."
            case .typography: "Roles on the system font. Every one scales with Dynamic Type."
            case .layout: "A 4-point spacing scale and continuous, concentric corner radii."
            case .lines: "Mode icons and line pills in the MTA's style. Colours come from the feed."
            case .journeys: "Legs to scale: walks as grey dots, rides in the line's colour."
            case .departures: "Next departures, and how sure each time is."
            }
        }
    }

    /// A debug-only catalogue of GlassUI's tokens and components, one section per ``GallerySection``. The app shows
    /// it through the screenshot harness (`-screenshot gallery`, or `gallery-<section>` for one section).
    public struct GlassUIGallery: View {
        private let sections: [GallerySection]
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        /// A gallery of `sections`, in order; every section by default.
        public init(sections: [GallerySection] = GallerySection.allCases) {
            self.sections = sections
        }

        public var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.xl) {
                        ForEach(sections) { section in
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                if sections.count > 1 {
                                    Text(section.title)
                                        .typography(.sectionTitle)
                                        .accessibilityAddTraits(.isHeader)
                                }
                                // At accessibility sizes the summary would fill the screen before any token.
                                if !dynamicTypeSize.isAccessibilitySize {
                                    Text(section.summary)
                                        .typography(.secondary)
                                        .foregroundStyle(.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                content(for: section)
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.screenInset)
                    .padding(.bottom, Spacing.xl)
                }
                .background(.canvasGrouped)
                .navigationTitle(sections.count == 1 ? sections[0].title : "GlassUI")
            }
        }

        @ViewBuilder
        private func content(for section: GallerySection) -> some View {
            switch section {
            case .colors: ColorsGallery()
            case .modes: ModesGallery()
            case .typography: TypographyGallery()
            case .layout: LayoutGallery()
            case .lines: LinesGallery()
            case .journeys: JourneysGallery()
            case .departures: DeparturesGallery()
            }
        }
    }

    // MARK: - Building blocks

    /// A titled group of gallery content on an opaque card.
    struct GalleryCard<Content: View>: View {
        var title: String?
        @ViewBuilder var content: Content

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                if let title {
                    Text(title.uppercased())
                        .typography(.captionEmphasized)
                        .foregroundStyle(.textSecondary)
                        .accessibilityAddTraits(.isHeader)
                }
                content
            }
            .padding(Spacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.surface, in: Radius.shape(Radius.lg))
        }
    }

    /// A row that lays out side by side, or stacked at accessibility text sizes.
    struct AdaptiveRow<Content: View>: View {
        private let spacing: CGFloat
        private let content: Content
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        init(spacing: CGFloat = Spacing.sm, @ViewBuilder content: () -> Content) {
            self.spacing = spacing
            self.content = content()
        }

        var body: some View {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xs))
                : AnyLayout(HStackLayout(alignment: .center, spacing: spacing))
            layout { content }
        }
    }

    /// A token's name in code, such as `.textPrimary`.
    struct TokenName: View {
        var name: String

        init(_ name: String) {
            self.name = name
        }

        var body: some View {
            Text(name)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.textSecondary)
        }
    }

    #Preview("Gallery") {
        GlassUIGallery()
    }

    #Preview("Gallery, dark, AX5") {
        GlassUIGallery()
            .preferredColorScheme(.dark)
            .dynamicTypeSize(.accessibility5)
    }
#endif
