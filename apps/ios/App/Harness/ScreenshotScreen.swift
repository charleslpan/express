import GlassUI
import SwiftUI
import TransitKit

/// The screens the screenshot harness can show, selected with `-screenshot <rawValue>`.
/// To add a screen, add a case here and a test in `UITests/ScreenshotTests.swift` (see AGENTS.md).
enum ScreenshotScreen: String, CaseIterable {
    /// The map home with its sheet at each detent (S2).
    case homePeek = "home-peek"
    case homeHalf = "home-half"
    case homeFull = "home-full"
    /// The map home while the user is outside New York, with the banner saying Express covers the city (S2).
    case homeOutsideNYC = "home-outside-nyc"
    /// The Nearby section in the home sheet at Union Square (N1): its peek (the nearest station's next trains), half,
    /// and full, with live and scheduled rows.
    case nearbyPeek = "nearby-peek"
    case nearbyHalf = "nearby-half"
    case nearbyFull = "nearby-full"
    /// Nearby's states other than departures (N1), each at half height: the "may not be real time" notice (with
    /// `-fixtures nyc-evening-stale`), the location turned off, outside New York, loading (`slow-network`), offline
    /// (`offline`), and nothing due (`nyc-no-service`).
    case nearbyStale = "nearby-stale"
    case nearbyDenied = "nearby-denied"
    case nearbyOutsideNYC = "nearby-outside-nyc"
    case nearbyLoading = "nearby-loading"
    case nearbyError = "nearby-error"
    case nearbyEmpty = "nearby-empty"
    /// Place search in the home sheet (S3): the hint for an empty query, a query typed while suggestions load, the
    /// suggestions, none found, a failure with Try Again, and "Search Unavailable" without a key. Which of the last
    /// states shows depends on the fixtures each test launches with.
    case searchEmpty = "search-empty"
    case searchTyping = "search-typing"
    case searchResults = "search-results"
    case searchNoResults = "search-no-results"
    case searchError = "search-error"
    case searchNoKey = "search-no-key"
    /// A place picked from search: its pin on the map and its card in the home sheet (S3), not saved (P1).
    case searchPlace = "search-place"
    /// Place search before you type, listing your recents with Clear (P1).
    case searchRecents = "search-recents"
    /// The place card for a saved place (P1).
    case placeSaved = "place-saved"
    /// The place card's Home or Work menu, open, for the place that's Work (P1); the UI test opens it.
    case placeHomeWork = "place-home-work"
    /// The home sheet at half height with the Home and Work chips, set and not set (P2).
    case homePlaces = "home-places"
    case homePlacesUnset = "home-places-unset"
    /// The home sheet's Saved section (P2), scrolled into view by the UI test: several places, one row still loading
    /// (on `slow-network`), and empty.
    case homeSaved = "home-saved"
    case homeSavedLoading = "home-saved-loading"
    case homeSavedEmpty = "home-saved-empty"
    /// Journey options to a picked place (J1): the options list at each detent, the second option selected on the map,
    /// the arrive-by picker, and every state: loading, none found, outside New York, location off, offline, and times
    /// that may not be real time. Which state shows depends on the fixtures and location each test launches with.
    case journeysPeek = "journeys-peek"
    case journeysHalf = "journeys-half"
    case journeysFull = "journeys-full"
    case journeysRoute = "journeys-route"
    case journeysArriveBy = "journeys-arrive-by"
    case journeysLoading = "journeys-loading"
    case journeysNoResults = "journeys-no-results"
    case journeysOutsideNYC = "journeys-outside-nyc"
    case journeysLocationOff = "journeys-location-off"
    case journeysError = "journeys-error"
    case journeysStale = "journeys-stale"
    /// A journey step by step (J2), pushed over its options: the 6 running late (subway only), the L and the M101 with
    /// a transfer, the Q and the shuttle with a tight transfer, the 6 cancelled (`nyc-evening-cancelled`), times that
    /// may not be real time (`nyc-evening-stale`), and the 6's stops between unfolded.
    case journeySubway = "journey-subway"
    case journeyBus = "journey-bus"
    case journeyTight = "journey-tight"
    case journeyCancelled = "journey-cancelled"
    case journeyStale = "journey-stale"
    case journeyStops = "journey-stops"
    /// The About sheet over the home sheet (S1).
    case about
    /// Liquid Glass controls and a glass sheet over the Google map, for judging the look (F5).
    case mapGlass = "map-glass"
    /// Live subway trains over Midtown and Union Square, and the same map zoomed out, where they hide (V1).
    case trains
    case trainsZoomedOut = "trains-zoomed-out"
    /// Live buses over Midtown and Union Square (alone, or with trains, by the fixtures), and zoomed out, where they
    /// hide (V2).
    case buses
    case busesZoomedOut = "buses-zoomed-out"
    /// Union Square's full departures board pushed in the home sheet (N2), at half and full height, and in its other
    /// states at half: times that may not be real time (`nyc-evening-stale`), offline (`offline`), and no more
    /// departures today (`nyc-no-service`).
    case stopHalf = "stop-half"
    case stopFull = "stop-full"
    case stopStale = "stop-stale"
    case stopError = "stop-error"
    case stopEmpty = "stop-empty"
    /// The uptown 6 followed from Union Square's board (N2): mid-route at half and full height, a trip that has
    /// ended, and offline (`offline`).
    case trip
    case tripFull = "trip-full"
    case tripEnded = "trip-ended"
    case tripError = "trip-error"
    /// Service alerts (A3), with `-fixtures nyc-alerts`: banners on Nearby's rows at full height, the alert chip at
    /// half height, and an alert's full text, which the UI test opens by tapping a banner.
    case alertsNearby = "alerts-nearby"
    case alertsChip = "alerts-chip"
    case alertDetail = "alert-detail"
    /// Line status (A3), pushed onto the home sheet: mixed lines (`nyc-alerts`), all good service (`nyc-evening`),
    /// loading (`slow-network`), and offline (`offline`).
    case lineStatus = "line-status"
    /// Union Square's board (N2) with `-fixtures nyc-alerts`: the stop's alerts under its name, and a banner on each
    /// line and direction they apply to (A3).
    case stopAlerts = "stop-alerts"

    #if DEBUG
        /// GlassUI's gallery, every section (debug builds only).
        case gallery
        /// One section of GlassUI's gallery each, so a screenshot shows the whole section.
        case galleryColors = "gallery-colors"
        case galleryModes = "gallery-modes"
        case galleryTypography = "gallery-typography"
        case galleryLayout = "gallery-layout"
        case galleryLines = "gallery-lines"
        case galleryJourneys = "gallery-journeys"
        case galleryDepartures = "gallery-departures"
        case galleryControls = "gallery-controls"
        case galleryControlStates = "gallery-control-states"
        case galleryControlFallbacks = "gallery-control-fallbacks"
    #endif

    @MainActor @ViewBuilder
    var view: some View {
        switch self {
        case .homePeek, .homeHalf, .homeFull, .homeOutsideNYC, .about, .nearbyPeek, .nearbyHalf, .nearbyFull,
             .nearbyStale, .nearbyDenied, .nearbyOutsideNYC, .nearbyLoading, .nearbyError, .nearbyEmpty, .searchEmpty,
             .searchTyping, .searchResults, .searchNoResults, .searchError, .searchNoKey, .searchPlace, .searchRecents,
             .placeSaved, .placeHomeWork, .homePlaces, .homePlacesUnset, .homeSaved, .homeSavedLoading,
             .homeSavedEmpty, .stopHalf, .stopFull, .stopStale, .stopError, .stopEmpty, .trip, .tripFull, .tripEnded,
             .tripError, .journeysPeek, .journeysHalf, .journeysFull, .journeysRoute, .journeysArriveBy,
             .journeysLoading, .journeysNoResults, .journeysOutsideNYC, .journeysLocationOff, .journeysError,
             .journeysStale, .journeySubway, .journeyBus, .journeyTight, .journeyCancelled, .journeyStale,
             .journeyStops, .alertsNearby, .alertsChip, .alertDetail, .lineStatus, .stopAlerts:
            RootView()
        case .mapGlass: MapGlassScreen()
        case .trains: GoView(camera: MapCamera(center: Self.midtown, zoom: 14.5))
        case .trainsZoomedOut: GoView(camera: MapCamera(center: Self.midtown, zoom: 11.5))
        case .buses: GoView(camera: MapCamera(center: Self.midtown, zoom: 15))
        case .busesZoomedOut: GoView(camera: MapCamera(center: Self.midtown, zoom: 13))
        #if DEBUG
            case .gallery: GlassUIGallery()
            case .galleryColors: GlassUIGallery(sections: [.colors])
            case .galleryModes: GlassUIGallery(sections: [.modes])
            case .galleryTypography: GlassUIGallery(sections: [.typography])
            case .galleryLayout: GlassUIGallery(sections: [.layout])
            case .galleryLines: GlassUIGallery(sections: [.lines])
            case .galleryJourneys: GlassUIGallery(sections: [.journeys])
            case .galleryDepartures: GlassUIGallery(sections: [.departures])
            case .galleryControls: GlassUIGallery(sections: [.controls])
            case .galleryControlStates: GlassUIGallery(sections: [.controlStates])
            case .galleryControlFallbacks: GlassUIGallery(sections: [.controlFallbacks])
        #endif
        }
    }

    /// How far the home sheet is pulled up for this screen.
    var homeDetent: HomeSheetDetent {
        switch self {
        case .homeHalf, .homePlaces, .homePlacesUnset, .nearbyHalf, .nearbyStale, .nearbyDenied, .nearbyOutsideNYC,
             .nearbyLoading, .nearbyError, .nearbyEmpty, .stopHalf, .stopStale, .stopError, .stopEmpty, .trip,
             .tripEnded, .tripError, .alertsChip, .alertDetail: .half
        case .homeFull, .homeSaved, .homeSavedLoading, .homeSavedEmpty, .nearbyFull, .stopFull, .tripFull,
             .journeysFull, .journeysArriveBy, .journeyBus, .journeyTight, .journeyStops, .alertsNearby, .lineStatus,
             .stopAlerts: .full
        case .journeysPeek: .peek
        case _ where isJourneys || isJourneyDetail: .half
        default: .peek
        }
    }

    /// The sheet the shell opens with for this screen.
    var sheet: AppSheet? {
        self == .about ? .about : nil
    }

    /// The query a search screen opens with, as if typed; nil leaves the field empty.
    var searchQuery: String? {
        switch self {
        case .searchEmpty, .searchNoKey, .searchRecents: ""
        case .searchTyping: "Grand Cen"
        case .searchResults, .searchError: "Grand"
        case .searchNoResults: "Qwxyz"
        default: nil
        }
    }

    /// Whether this is one of the journey options screens (J1).
    var isJourneys: Bool {
        rawValue.hasPrefix("journeys-")
    }

    /// Whether this is one of the journey detail screens (J2).
    var isJourneyDetail: Bool {
        rawValue.hasPrefix("journey-")
    }

    /// The journey a journey detail screen opens, by its id in the fixtures (``FixtureSet/journey(id:)``).
    private var journeyID: String? {
        switch self {
        case .journeySubway, .journeyCancelled, .journeyStale, .journeyStops: "fixture-6"
        case .journeyBus: "fixture-l-m101"
        case .journeyTight: "fixture-q-s"
        default: nil
        }
    }

    /// Puts the router where this screen starts: searching, showing a picked place or journeys to it, or with a stop
    /// or trip pushed.
    @MainActor
    func prepare(_ router: AppRouter) {
        if self == .lineStatus {
            router.showLineStatus(nearbyBuses: FixtureSet.unionSquareBuses)
        } else if searchQuery != nil {
            router.showPlaceSearch()
        } else if [.searchPlace, .placeSaved, .placeHomeWork].contains(self) {
            router.showPlace(FixturePlaceSearchService.places[0])
        } else if isJourneys {
            let place = FixturePlaceSearchService.places[0]
            router.showPlace(place)
            var query = JourneyQuery(to: .place(place))
            if self == .journeysArriveBy {
                // 7:30 PM, an hour after the fixtures' "now".
                query.time = .arriveBy(FixtureSet.nycEvening.referenceDate.addingTimeInterval(3600))
            }
            router.showJourneys(query)
            router.homeDetent = homeDetent
        } else if let journeyID, let journey = FixtureSet.journey(id: journeyID) {
            let place = FixturePlaceSearchService.places[0]
            router.showPlace(place)
            router.showJourneys(JourneyQuery(to: .place(place)))
            router.showJourneyDetail(journey, to: place.name)
            router.homeDetent = homeDetent
        }
        let unionSquare = StopRoute(stopId: "us-ny-MTA-NYCSubway_635", name: "14 St-Union Sq", isSubway: true)
        switch self {
        case .stopHalf, .stopFull, .stopStale, .stopError, .stopEmpty, .stopAlerts:
            router.homePath.append(unionSquare)
        case .trip, .tripFull, .tripError:
            router.homePath.append(unionSquare)
            router.homePath.append(TripRoute(tripId: "fixture-6-0-4", stationId: unionSquare.stopId))
        case .tripEnded:
            router.homePath.append(TripRoute(tripId: "fixture-6-0-ended"))
        default:
            break
        }
    }

    /// Where the journey options screen starts: the second option selected, or the time picker open.
    var journeyOptionsSeed: JourneyOptionsSeed? {
        switch self {
        case .journeysRoute: JourneyOptionsSeed(selectedOption: 1)
        case .journeysArriveBy: JourneyOptionsSeed(editsTime: true)
        case _ where isJourneys: JourneyOptionsSeed()
        default: nil
        }
    }

    /// Where the journey detail screen starts: the stops between unfolded, or folded as they open.
    var journeyDetailSeed: JourneyDetailSeed? {
        switch self {
        case .journeyStops: JourneyDetailSeed(showsStops: true)
        case _ where isJourneyDetail: JourneyDetailSeed()
        default: nil
        }
    }

    /// Fills the in-memory place store with what this screen shows: recents picked over the past day, or the
    /// card's place saved, or Work with another place as Home, or Home and Work set, or several saved places whose
    /// details are fetched again as at launch (one of them never arriving on `slow-network`).
    @MainActor
    func prepare(_ places: PlaceStore) {
        let fixtures = FixturePlaceSearchService.places
        switch self {
        case .searchRecents:
            let now = FixtureSet.nycEvening.referenceDate
            for (place, minutesAgo) in zip([fixtures[0], fixtures[1], fixtures[2], fixtures[4]], [5, 90, 1440, 4320]) {
                places.addRecent(place, pickedAt: now.addingTimeInterval(-Double(minutesAgo) * 60))
            }
        case .placeSaved:
            places.save(fixtures[0])
        case .placeHomeWork, .homePlaces:
            places.set(.home, to: fixtures[2])
            places.set(.work, to: fixtures[0])
        case .homeSaved:
            for place in [fixtures[0], fixtures[2], fixtures[4], fixtures[3]] {
                places.save(place)
                places.details.forget(place.placeID)
            }
        case .homeSavedLoading:
            for place in [fixtures[0], fixtures[2], fixtures[4]] {
                places.save(place)
            }
            places.details.forget(fixtures[2].placeID)
        default:
            break
        }
    }

    /// The location permission the screen shows; the harness never asks for it.
    var locationAuthorization: LocationService.Authorization {
        switch self {
        case .homeOutsideNYC, .nearbyPeek, .nearbyHalf, .nearbyFull, .nearbyStale, .nearbyOutsideNYC, .nearbyLoading,
             .nearbyError, .nearbyEmpty, .alertsNearby, .alertsChip, .alertDetail: .authorized
        case .nearbyDenied, .journeysLocationOff: .denied
        case _ where isJourneys || isJourneyDetail: .authorized
        default: .notDetermined
        }
    }

    /// Where the trains and buses screens look: between Union Square and Herald Square, where the `nyc-evening` trips
    /// and buses run.
    private static let midtown = Coordinate(latitude: 40.7445, longitude: -73.9895)

    /// The accessibility identifier the harness puts on the screen, which the UI test waits for before capturing.
    var accessibilityIdentifier: String {
        "screenshot.\(rawValue)"
    }
}

/// Kept apart from the enum's body so it stays within SwiftLint's type length.
extension ScreenshotScreen {
    /// The location the screen shows the user at, if any: Philadelphia's City Hall outside New York, and Union Square
    /// (``FixtureSet/unionSquare``) for Nearby and journeys.
    var location: Coordinate? {
        switch self {
        case .homeOutsideNYC, .nearbyOutsideNYC, .journeysOutsideNYC: Coordinate(latitude: 39.9526, longitude: -75.1652)
        case .nearbyPeek, .nearbyHalf, .nearbyFull, .nearbyStale, .nearbyLoading, .nearbyError, .nearbyEmpty,
             .alertsNearby, .alertsChip, .alertDetail:
            FixtureSet.unionSquare
        case .journeysLocationOff: nil
        case _ where isJourneys || isJourneyDetail: FixtureSet.unionSquare
        default: nil
        }
    }
}
