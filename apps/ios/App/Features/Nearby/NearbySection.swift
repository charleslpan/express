import GlassUI
import SwiftUI
import TransitKit
import UIKit

/// The home sheet's Nearby section: the stops nearest the rider, subway stations and bus stops, each with its next
/// departures by line and direction, the nearest subway station first. Its first two rows are what the sheet shows at
/// its peek (``View/homeSheetPeekBoundary(_:)``): the next trains at the nearest station.
///
/// It refreshes about every 30 seconds while it's on screen and the app is active, and pauses otherwise. It asks for
/// the location only when the rider taps "Use My Location", and says so plainly when it can't show departures: the
/// location is off, the rider is outside New York, the server can't be reached, or nothing is due.
struct NearbySection: View {
    @Environment(AppRouter.self) private var router
    @Environment(LocationService.self) private var location
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.transitClient) private var transitClient
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = NearbyModel()
    /// Bumped by "Try Again", which restarts refreshing.
    @State private var attempt = 0

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("nearby.\(state.identifier)")
            .task(id: refresh) {
                guard refresh.isActive else { return }
                await model.run(client: transitClient, location: { location.location }, now: { environment.now })
            }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .needsPermission:
            NearbyMessage(
                "See What's Leaving Near You",
                systemImage: "location",
                message: "Express uses your location to show the next trains and buses at the stops around you."
            ) {
                Button("Use My Location") {
                    location.requestLocation()
                }
                .accessibilityHint("Asks to use your location while you're using Express.")
            }
        case let .locationOff(authorization):
            NearbyMessage(
                "Location Is Off",
                systemImage: "location.slash",
                message: authorization == .restricted
                    ? "Location access is restricted on this iPhone, so Express can't find stops near you."
                    : "Turn on Location Services for Express in Settings to see departures near you."
            ) {
                if authorization == .denied, let settings = URL(string: UIApplication.openSettingsURLString) {
                    Link("Open Settings", destination: settings)
                        .accessibilityHint("Opens Express's settings, where you can let it use your location.")
                }
            }
        case .outsideServiceArea:
            NearbyMessage(
                "Nearby Is for New York",
                systemImage: "building.2",
                message: """
                Express shows departures across New York City's five boroughs. \
                Once you're there, the next trains and buses near you will show here.
                """
            ) {}
        case .locating, .loading:
            NearbyLoadingRows(label: state == .locating ? "Finding stops near you" : "Loading departures near you")
        case .empty:
            NearbyMessage(
                "Nothing Due Nearby",
                systemImage: "moon.zzz",
                message: "No trains or buses are due at the stops near you in the next half hour."
            ) {}
        case let .failed(error):
            NearbyMessage(
                error == .offline ? "You're Offline" : "Can't Load Departures",
                systemImage: error == .offline ? "wifi.slash" : "exclamationmark.triangle",
                message: error == .offline
                    ? "Departures near you will show once you're connected."
                    : "Express couldn't reach its server. Try again in a moment."
            ) {
                Button("Try Again") {
                    attempt += 1
                }
            }
        case let .loaded(board, realtimeIsStale):
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if realtimeIsStale {
                    NotRealTimeNotice()
                }
                ForEach(Array(board.stops.enumerated()), id: \.element.id) { index, stop in
                    NearbyStopView(
                        departures: stop,
                        lineLimit: index == 0 ? nil : 4,
                        now: model.now,
                        realtimeIsStale: realtimeIsStale,
                        marksPeek: index == 0
                    ) { line in
                        router.showDepartures(line, at: stop.stop)
                    }
                }
            }
        }
    }

    /// What the section shows: the location's state first, then the board's.
    private var state: NearbyState {
        switch location.authorization {
        case .notDetermined: return .needsPermission
        case .denied, .restricted: return .locationOff(location.authorization)
        case .authorized: break
        }
        guard let fix = location.location else { return .locating }
        guard ServiceArea.nyc.contains(fix) else { return .outsideServiceArea }
        switch model.content {
        case .idle, .loading: return .loading
        case let .failed(error): return .failed(error)
        case let .loaded(board):
            return board.isEmpty ? .empty : .loaded(board, realtimeIsStale: board.mayNotBeRealTime(at: model.now))
        }
    }

    /// Refreshing runs while this says so, and restarts when it changes.
    private var refresh: RefreshKey {
        let canLoad = location.authorization == .authorized
            && location.location.map(ServiceArea.nyc.contains) == true
        // Place search takes the sheet's place, and the About sheet covers it.
        let isVisible = scenePhase == .active && router.sheet == nil && !router.isSearchingPlaces
        return RefreshKey(isActive: canLoad && isVisible, attempt: attempt)
    }

    private struct RefreshKey: Equatable {
        var isActive: Bool
        var attempt: Int
    }
}

/// What the Nearby section shows.
private enum NearbyState: Equatable {
    case needsPermission
    case locationOff(LocationService.Authorization)
    case locating
    case outsideServiceArea
    case loading
    case loaded(NearbyBoard, realtimeIsStale: Bool)
    case empty
    case failed(TransitError)

    /// The suffix of the section's accessibility identifier (`nearby.loaded`), which the screenshot harness waits on.
    var identifier: String {
        switch self {
        case .needsPermission: "permission"
        case .locationOff: "location-off"
        case .locating: "locating"
        case .outsideServiceArea: "outside-nyc"
        case .loading: "loading"
        case .loaded: "loaded"
        case .empty: "empty"
        case .failed: "failed"
        }
    }
}

/// The notice the MTA's terms require while times may not be real time: the board is over a minute old.
private struct NotRealTimeNotice: View {
    var body: some View {
        Label {
            Text("Times may not be real time")
                .foregroundStyle(.textPrimary)
        } icon: {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .foregroundStyle(.statusDelayed)
        }
        .typography(.captionEmphasized)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(.fill.tertiary, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("nearby.not-real-time")
    }
}

#Preview("Nearby, permission") {
    ScrollView {
        NearbySection()
            .padding()
    }
    .environment(AppRouter())
    .environment(LocationService(fixed: .notDetermined))
    .environment(AppEnvironment())
}

#Preview("Nearby, Union Square") {
    ScrollView {
        NearbySection()
            .padding()
    }
    .environment(AppRouter())
    .environment(LocationService(fixed: .authorized, location: FixtureSet.unionSquare))
    .environment(AppEnvironment(fixtures: .nycEvening))
    .environment(\.transitClient, FixtureSet.nycEvening.transitClient)
}
