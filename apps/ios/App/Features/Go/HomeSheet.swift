import GlassUI
import SwiftUI
import UIKit

/// The home sheet that stays over the map, Apple Maps style: ``HomeSheetContent`` scrolling in its own navigation
/// stack (``AppRouter/homePath``), place search (``PlaceSearchPanel``) in its place while
/// ``AppRouter/isSearchingPlaces``, or the picked place's ``PlaceCard`` while there is one. It brings no
/// background of its own, so the system sheet draws its glass, and it presents the router's sheets (About) on top.
/// ``GoView`` presents it with its detents.
struct HomeSheet: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.homePath) {
            Group {
                if router.isSearchingPlaces {
                    PlaceSearchPanel()
                } else if let place = router.selectedPlace {
                    PlaceCard(place: place) {
                        router.closePlace()
                    }
                } else {
                    ScrollView {
                        HomeSheetContent {
                            router.showPlaceSearch()
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

/// The home sheet's peek: tall enough for the search field at the current text size (which stops growing at AX2),
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
    /// The system detent for this one.
    var presentationDetent: PresentationDetent {
        switch self {
        case .peek: .custom(HomePeekDetent.self)
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

#Preview("Home sheet") {
    Color.gray
        .sheet(isPresented: .constant(true)) {
            HomeSheet()
                .presentationDetents([.custom(HomePeekDetent.self), .medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .interactiveDismissDisabled()
        }
        .environment(AppRouter(homeDetent: .half))
}
