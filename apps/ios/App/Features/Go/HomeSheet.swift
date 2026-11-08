import GlassUI
import SwiftUI
import UIKit

/// The home sheet that stays over the map, Apple Maps style: ``HomeSheetContent`` scrolling in its own navigation
/// stack (``AppRouter/homePath``), or place search in its place while ``AppRouter/isSearchingPlaces``. It brings no
/// background of its own, so the system sheet draws its glass, and it presents the router's sheets (About) on top.
/// ``GoView`` presents it with its detents.
///
/// It measures how tall its peek should be, from the search field down to what the content marks with
/// ``View/homeSheetPeekBoundary(_:)``, into `peekHeight`; nil while nothing is marked.
struct HomeSheet: View {
    @Binding var peekHeight: CGFloat?
    @Environment(AppRouter.self) private var router
    /// The Nearby board, kept here so it survives place search replacing the sheet's content.
    @State private var nearby = NearbyModel()

    init(peekHeight: Binding<CGFloat?>) {
        _peekHeight = peekHeight
    }

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.homePath) {
            Group {
                if router.isSearchingPlaces {
                    PlaceSearchPlaceholder {
                        router.endPlaceSearch()
                    }
                } else {
                    ScrollView {
                        HomeSheetContent(nearby: nearby) {
                            router.showPlaceSearch()
                        }
                        .backgroundPreferenceValue(HomePeekBoundary.self) { boundary in
                            GeometryReader { proxy in
                                // Measured in the content's own space, so scrolling doesn't move it.
                                let bottom = boundary.map { proxy[$0].maxY }
                                Color.clear
                                    .onAppear { updatePeek(bottom) }
                                    .onChange(of: bottom) { _, bottom in updatePeek(bottom) }
                            }
                        }
                        .padding(.top, Spacing.lg)
                    }
                }
            }
            .toolbarVisibility(.hidden, for: .navigationBar)
        }
        .sheet(item: $router.sheet) { sheet in
            switch sheet {
            case .about: AboutView()
            }
        }
    }
}

extension HomeSheet {
    /// The tallest the peek grows, so it stays under the half-height detent at the largest text sizes.
    static let maxPeekHeight: CGFloat = 400

    /// Sets the peek to show the content down to `bottom` (in the content's space), with the same room around it
    /// as ``HomePeekDetent`` gives the search field; whole points only, so layout rounding doesn't move the sheet.
    private func updatePeek(_ bottom: CGFloat?) {
        let height = bottom.map { min((Spacing.lg + $0 + Spacing.lg).rounded(.up), Self.maxPeekHeight) }
        if height != peekHeight {
            peekHeight = height
        }
    }
}

/// The home sheet's peek while no content marks a peek boundary: tall enough for the search field at the current text
/// size (which stops growing at AX2),
/// with room above it for the grabber and below it for the sheet's edge.
struct HomePeekDetent: CustomPresentationDetent {
    static func height(in context: Context) -> CGFloat? {
        let size = min(context.dynamicTypeSize, .accessibility2)
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(size))
        let field = UIFontMetrics(forTextStyle: .body).scaledValue(for: HomeSearchField.height, compatibleWith: traits)
        return Spacing.lg + field + Spacing.lg
    }
}

extension HomeSheetDetent {
    /// The system detent for this one, with the peek `peekHeight` tall where the content measured one
    /// (``HomeSheet``).
    func presentationDetent(peekHeight: CGFloat?) -> PresentationDetent {
        switch self {
        case .peek: peekHeight.map { .height($0) } ?? .custom(HomePeekDetent.self)
        case .half: .medium
        case .full: .large
        }
    }

    /// The detent for a system one, which is always one of the three the home sheet offers.
    init(_ detent: PresentationDetent) {
        switch detent {
        case .large: self = .full
        case .medium: self = .half
        default: self = .peek
        }
    }
}

/// Stands in for place search (S3) in the home sheet: a heading, a way back, and what search will do.
private struct PlaceSearchPlaceholder: View {
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                HomeSectionHeading("Search")
                Spacer(minLength: Spacing.xs)
                Button("Cancel", action: onCancel)
                    .typography(.body)
            }
            ContentUnavailableView(
                "Where To?",
                systemImage: "magnifyingglass",
                description: Text("Search for a place, an address, or a station to plan a trip there.")
            )
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.lg)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

#Preview("Home sheet") {
    Color.gray
        .sheet(isPresented: .constant(true)) {
            HomeSheet(peekHeight: .constant(nil))
                .presentationDetents([.custom(HomePeekDetent.self), .medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .interactiveDismissDisabled()
        }
        .environment(AppRouter(homeDetent: .half))
        .environment(LocationService(fixed: .notDetermined))
        .environment(AppEnvironment())
}
