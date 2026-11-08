import Foundation
import Observation
import SwiftUI
import TransitKit

/// Live subway trains for the map: fetches the trips running in the area on screen and works out where each train is
/// between its stations, for ``MapView``'s vehicles.
///
/// The subway has no GPS, so positions are estimates: MOTIS's `map/trips` gives each hop's departure and arrival
/// (with realtime delays), and a train moves along the hop's track in proportion to the time gone. Positions are
/// worked out again every couple of seconds and the markers glide between them; the trips are fetched again when the
/// map settles and every 30 seconds while it shows, never in the background, and a move cancels a fetch in flight.
///
/// Wire it up with ``SwiftUI/View/liveTrains(_:)`` on the map, and pass ``cameraDidIdle(_:)`` and
/// ``cameraDidMove()`` to ``MapView``.
@MainActor
@Observable
final class LiveTrains {
    /// How often trains move on the map.
    static let tick: Duration = .seconds(2)
    /// How often the trips are fetched again while the map shows.
    static let refreshInterval: TimeInterval = 30
    /// How far ahead each fetch asks for trips: past the next refresh, with room for responses the CDN cached.
    static let window: TimeInterval = 120
    /// How old the last fetch may be before positions may not be real time, per the MTA's terms.
    static let realTimeLimit = RealtimeDataAge.realTimeLimit

    /// The trains to draw, at their estimated positions now.
    private(set) var vehicles: [MapVehicle] = []
    /// Whether the map should say positions may not be real time: trains show, and the subway's live data, or the
    /// last fetch, is more than a minute old.
    private(set) var mayNotBeRealTime = false

    let visibility = TrainVisibility()
    @ObservationIgnored private var runs: [TrainRun] = []
    @ObservationIgnored private var viewport: MapViewport?
    @ObservationIgnored private var dataAge: RealtimeDataAge?
    @ObservationIgnored private var fetchedAt: Date?
    @ObservationIgnored private var attemptedAt: Date?
    @ObservationIgnored private var fetch: Task<Void, Never>?
    @ObservationIgnored private var client: TransitClient?
    @ObservationIgnored private var now: @MainActor () -> Date = { .now }

    /// The map came to rest: show the trains in its area, and fetch them afresh.
    func cameraDidIdle(_ viewport: MapViewport) {
        self.viewport = viewport
        guard visibility.showsTrains(atZoom: viewport.zoom) else {
            // Zoomed out: forget the trains rather than fetch the whole city's.
            cancelFetch()
            runs = []
            fetchedAt = nil
            update()
            return
        }
        update()
        refresh()
    }

    /// The map started to move: what's in flight is for an area it's leaving.
    func cameraDidMove() {
        cancelFetch()
    }

    /// Moves the trains and refreshes them on a timer until cancelled, such as when the app leaves the foreground.
    ///
    /// - Parameters:
    ///   - client: Where trips come from.
    ///   - now: The current time; the screenshot harness's fixed clock where it runs on fixtures.
    func run(client: TransitClient, now: @escaping @MainActor () -> Date) async {
        self.client = client
        self.now = now
        refresh()
        while !Task.isCancelled {
            update()
            if let attemptedAt, now().timeIntervalSince(attemptedAt) >= Self.refreshInterval {
                refresh()
            }
            try? await Task.sleep(for: Self.tick)
        }
        cancelFetch()
        self.client = nil
    }

    /// Fetches the trips in the map's area (and a margin round it), with how old the subway's live data is.
    private func refresh() {
        guard let client, let viewport, visibility.showsTrains(atZoom: viewport.zoom) else { return }
        cancelFetch()
        let start = now()
        attemptedAt = start
        let bounds = viewport.bounds.padded(by: 0.25)
        let zoom = viewport.zoom.rounded(.down)
        let end = start.addingTimeInterval(Self.window)
        fetch = Task {
            async let segments = client.tripSegments(in: bounds, zoom: zoom, from: start, to: end)
            async let age = client.realtimeDataAge()
            let fetched = try? await segments
            let dataAge = try? await age
            guard !Task.isCancelled else { return }
            if let fetched {
                runs = TrainRun.runs(from: fetched)
                fetchedAt = start
            }
            // An age the server can't tell counts as unknown, which may not be real time.
            self.dataAge = dataAge ?? RealtimeDataAge(feedTimestamp: nil)
            update()
        }
    }

    private func cancelFetch() {
        fetch?.cancel()
        fetch = nil
    }

    /// Works out where each train is now, and whether to say it may not be real time.
    private func update() {
        guard let viewport else { return }
        let now = now()
        let positions = runs.compactMap { $0.position(at: now) }
        let visible = visibility.visible(positions, in: viewport.bounds, zoom: viewport.zoom)
        let vehicles = visible.map(MapVehicle.init(train:))
        if vehicles != self.vehicles {
            self.vehicles = vehicles
        }

        let fetchIsOld = fetchedAt.map { now.timeIntervalSince($0) > Self.realTimeLimit } ?? false
        let feedIsOld = dataAge?.mayNotBeRealTime(at: now) ?? false
        let mayNotBeRealTime = visibility.showsTrains(atZoom: viewport.zoom) && fetchedAt != nil
            && (fetchIsOld || feedIsOld)
        if mayNotBeRealTime != self.mayNotBeRealTime {
            self.mayNotBeRealTime = mayNotBeRealTime
        }
    }
}

extension MapVehicle {
    /// A train at its estimated position, read by VoiceOver as "Q train to 14 St-Union Sq, estimated position".
    init(train: TrainPosition) {
        let line = train.bullet.shape == .diamond ? "\(train.bullet.text) express" : train.bullet.text
        let place = train.fromStop == train.toStop
            ? String(localized: "\(line) train at \(train.toStop)")
            : String(localized: "\(line) train to \(train.toStop)")
        self.init(
            id: train.id,
            coordinate: train.coordinate,
            bearing: train.bearing,
            bullet: train.bullet,
            accessibilityLabel: String(localized: "\(place), estimated position")
        )
    }
}

extension View {
    /// Keeps `trains` moving and refreshed while the app is in the foreground, from the environment's transit client
    /// and clock, and pauses it in the background.
    func liveTrains(_ trains: LiveTrains) -> some View {
        modifier(LiveTrainsUpdates(trains: trains))
    }
}

private struct LiveTrainsUpdates: ViewModifier {
    let trains: LiveTrains
    @Environment(\.transitClient) private var client
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .task(id: scenePhase == .active) {
                guard scenePhase == .active else { return }
                await trains.run(client: client) { [environment] in environment.now }
            }
    }
}
