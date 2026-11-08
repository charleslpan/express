import GlassUI
import SwiftUI
import TransitKit
import UIKit

/// The home sheet's Nearby section: the stops nearest the rider, subway stations and bus stops, each with its next
/// departures by line and direction, the nearest subway station first. It comes in two parts around Home and Work:
/// ``Part/next``, the nearest station's next trains under the search field, which the sheet shows at its peek
/// (``View/homeSheetPeekBoundary(_:)``), and ``Part/more``, the station's other lines and the other stops, further
/// down. Both read one ``NearbyModel``.
///
/// The `next` part refreshes the model about every 30 seconds while it's on screen and the app is active, and pauses
/// otherwise. It asks for the location only when the rider taps "Use My Location", and says so plainly when it can't
/// show departures: the location is off, the rider is outside New York, the server can't be reached, or nothing is
/// due.
struct NearbySection: View {
    /// Which part of the section a view shows.
    enum Part {
        /// The nearest station's next departures, or what stands in their place; it also drives refreshing.
        case next
        /// The nearest station's other lines and the other stops near by, once departures have loaded.
        case more
    }

    /// How many of the nearest station's lines the `next` part shows.
    static let nextLineCount = 2

    let model: NearbyModel
    let part: Part
    @Environment(AppRouter.self) private var router
    @Environment(LocationService.self) private var location
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.transitClient) private var transitClient
    @Environment(\.scenePhase) private var scenePhase
    /// Bumped by "Try Again", which restarts refreshing.
    @State private var attempt = 0

    init(model: NearbyModel, part: Part) {
        self.model = model
        self.part = part
    }

    var body: some View {
        switch part {
        case .next:
            next
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("nearby.\(state.identifier)")
                .task(id: refresh) {
                    guard refresh.isActive else { return }
                    await model.run(client: transitClient, location: { location.location }, now: { environment.now })
                }
        case .more:
            if case let .loaded(board, realtimeIsStale) = state {
                more(board, realtimeIsStale: realtimeIsStale)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("nearby.more")
            }
        }
    }

    @ViewBuilder
    private var next: some View {
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
                if let nearest = board.stops.first {
                    NearbyStopView(
                        stop: nearest.stop,
                        lines: Array(nearest.lines.prefix(Self.nextLineCount)),
                        now: model.now,
                        realtimeIsStale: realtimeIsStale,
                        marksPeek: true
                    ) { line in
                        router.showDepartures(line, at: nearest.stop)
                    }
                }
            }
        }
    }

    /// The rest of the board under a heading: the nearest station's other lines, then up to four lines at each
    /// other stop.
    @ViewBuilder
    private func more(_ board: NearbyBoard, realtimeIsStale: Bool) -> some View {
        let sections = board.stops.enumerated().map { index, stop in
            (
                stop: stop.stop,
                lines: index == 0 ? Array(stop.lines.dropFirst(Self.nextLineCount)) : Array(stop.lines.prefix(4))
            )
        }.filter { !$0.lines.isEmpty }
        if !sections.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HomeSectionHeading("More Nearby")
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    ForEach(sections, id: \.stop.id) { section in
                        NearbyStopView(
                            stop: section.stop,
                            lines: section.lines,
                            now: model.now,
                            realtimeIsStale: realtimeIsStale,
                            marksPeek: false
                        ) { line in
                            router.showDepartures(line, at: section.stop)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
        NearbySection(model: NearbyModel(), part: .next)
            .padding()
    }
    .environment(AppRouter())
    .environment(LocationService(fixed: .notDetermined))
    .environment(AppEnvironment())
}

#Preview("Nearby, Union Square") {
    @Previewable @State var model = NearbyModel()
    ScrollView {
        VStack(spacing: Spacing.lg) {
            NearbySection(model: model, part: .next)
            NearbySection(model: model, part: .more)
        }
        .padding()
    }
    .environment(AppRouter())
    .environment(LocationService(fixed: .authorized, location: FixtureSet.unionSquare))
    .environment(AppEnvironment(fixtures: .nycEvening))
    .environment(\.transitClient, FixtureSet.nycEvening.transitClient)
}
