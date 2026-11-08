import Foundation
import Observation
import SwiftUI
import TransitKit

/// Live MTA buses for the map, at their GPS positions from our server's `/api/vehicles/bus`, for ``MapView``'s
/// vehicles beside ``LiveTrains``'s trains.
///
/// Buses show from zoom 14, thinned like trains (``VehicleVisibility``). They're fetched when the map settles on a
/// new area and every 30 seconds while it shows, never in the background, and a move cancels a fetch in flight. The
/// area asked for is snapped to a coarse grid (``TransitClient/busGridStep``), so the CDN answers nearby views from
/// its cache. Each route's label and colour come from the feed through MOTIS, fetched once per area and kept.
///
/// Wire it up with ``SwiftUI/View/liveBuses(_:)`` on the map, and pass ``cameraDidIdle(_:)`` and ``cameraDidMove()``
/// to ``MapView``.
@MainActor
@Observable
final class LiveBuses {
    /// How often the loop checks whether a refresh is due and whether the data has gone stale.
    static let tick: Duration = .seconds(5)
    /// How often the buses are fetched again while the map shows: Bus Time and our server's cache update every 30 s.
    static let refreshInterval: TimeInterval = 30

    /// The buses to draw.
    private(set) var vehicles: [MapVehicle] = []
    /// Whether the map should say positions may not be real time: buses show, and the feed, or the last fetch of
    /// it, is more than a minute old.
    private(set) var mayNotBeRealTime = false

    let visibility = VehicleVisibility(minimumZoom: 14, limit: 150)
    @ObservationIgnored private var positions: BusPositions?
    @ObservationIgnored private var styles: [String: BusRouteStyle] = [:]
    /// The areas whose route styles have been asked for, snapped, so each is asked once.
    @ObservationIgnored private var styledAreas: Set<CoordinateBounds> = []
    /// Each bus's heading as last shown, for buses whose fix has no bearing.
    @ObservationIgnored private var headings: [String: Double] = [:]
    @ObservationIgnored private var previous: [String: Bus] = [:]
    @ObservationIgnored private var shown: [String: Bus] = [:]
    @ObservationIgnored private var viewport: MapViewport?
    @ObservationIgnored private var fetchedArea: CoordinateBounds?
    @ObservationIgnored private var fetchedAt: Date?
    @ObservationIgnored private var attemptedAt: Date?
    @ObservationIgnored private var fetch: Task<Void, Never>?
    @ObservationIgnored private var client: TransitClient?
    @ObservationIgnored private var now: @MainActor () -> Date = { .now }

    /// The bus a map vehicle stands for, such as one that was tapped; `nil` for a train.
    func bus(forVehicle id: String) -> Bus? {
        shown[id]
    }

    /// The map came to rest: show the buses in its area, and fetch them where it's a new area.
    func cameraDidIdle(_ viewport: MapViewport) {
        self.viewport = viewport
        guard visibility.showsVehicles(atZoom: viewport.zoom) else {
            // Zoomed out: forget the buses rather than fetch the whole city's.
            cancelFetch()
            positions = nil
            fetchedArea = nil
            fetchedAt = nil
            update()
            return
        }
        update()
        if area(for: viewport) != fetchedArea || isRefreshDue {
            refresh()
        }
    }

    /// The map started to move: what's in flight is for an area it's leaving.
    func cameraDidMove() {
        cancelFetch()
    }

    /// Refreshes the buses on a timer until cancelled, such as when the app leaves the foreground.
    ///
    /// - Parameters:
    ///   - client: Where buses come from.
    ///   - now: The current time; the screenshot harness's fixed clock where it runs on fixtures.
    func run(client: TransitClient, now: @escaping @MainActor () -> Date) async {
        self.client = client
        self.now = now
        refresh()
        while !Task.isCancelled {
            if isRefreshDue {
                refresh()
            }
            update()
            try? await Task.sleep(for: Self.tick)
        }
        cancelFetch()
        self.client = nil
    }

    private var isRefreshDue: Bool {
        attemptedAt.map { now().timeIntervalSince($0) >= Self.refreshInterval } ?? true
    }

    /// The area to fetch for a viewport: what's on screen and a margin round it, snapped as the client asks for it.
    private func area(for viewport: MapViewport) -> CoordinateBounds {
        viewport.bounds.padded(by: 0.25).snapped(toGrid: TransitClient.busGridStep)
    }

    /// Fetches the buses in the map's area, and the route styles there if that area's are still unknown.
    private func refresh() {
        guard let client, let viewport, visibility.showsVehicles(atZoom: viewport.zoom) else { return }
        cancelFetch()
        let start = now()
        attemptedAt = start
        let area = area(for: viewport)
        let needsStyles = !styledAreas.contains(area)
        let zoom = viewport.zoom.rounded(.down)
        fetch = Task {
            async let buses = client.buses(in: area)
            async let routeStyles = Self.styles(needed: needsStyles, client: client, area: area, zoom: zoom)
            let fetched = try? await buses
            let styles = await routeStyles
            guard !Task.isCancelled else { return }
            if let styles {
                styledAreas.insert(area)
                self.styles.merge(styles) { _, new in new }
            }
            if let fetched {
                previous = positions.map { Dictionary($0.vehicles.map { ($0.id, $0) }) { first, _ in first } } ?? [:]
                positions = fetched
                fetchedArea = area
                fetchedAt = start
            }
            update()
        }
    }

    /// The route styles in `area` where they're `needed`; `nil` where they aren't, or the fetch failed (it's tried
    /// again with the next refresh).
    private nonisolated static func styles(
        needed: Bool,
        client: TransitClient,
        area: CoordinateBounds,
        zoom: Double
    ) async -> [String: BusRouteStyle]? {
        guard needed else { return nil }
        return try? await client.busRouteStyles(in: area, zoom: zoom)
    }

    private func cancelFetch() {
        fetch?.cancel()
        fetch = nil
    }

    /// Picks the buses to show, and whether to say they may not be real time.
    private func update() {
        guard let viewport else { return }
        let visible = visibility.visible(positions?.vehicles ?? [], in: viewport.bounds, zoom: viewport.zoom)
        var headings: [String: Double] = [:]
        let vehicles = visible.map { bus in
            let heading = bus.heading(after: previous[bus.id], previousHeading: self.headings[bus.id])
            headings[bus.id] = heading
            return MapVehicle(bus: bus, style: bus.route.flatMap { styles[$0] }, heading: heading)
        }
        self.headings = headings
        shown = Dictionary(visible.map { (MapVehicle.busID($0.id), $0) }) { first, _ in first }
        if vehicles != self.vehicles {
            self.vehicles = vehicles
        }

        let now = now()
        let fetchIsOld = fetchedAt.map { now.timeIntervalSince($0) > RealtimeDataAge.realTimeLimit } ?? false
        let feedIsOld = positions?.dataAge.mayNotBeRealTime(at: now) ?? false
        let mayNotBeRealTime = visibility.showsVehicles(atZoom: viewport.zoom) && fetchedAt != nil
            && (fetchIsOld || feedIsOld)
        if mayNotBeRealTime != self.mayNotBeRealTime {
            self.mayNotBeRealTime = mayNotBeRealTime
        }
    }
}

extension MapVehicle {
    /// The map's id for a bus, set apart from trains' trip ids.
    static func busID(_ id: String) -> String {
        "bus|\(id)"
    }

    /// A bus at its GPS position, read by VoiceOver as "M15-SBS bus" (or "M15-SBS bus, heading northeast").
    init(bus: Bus, style: BusRouteStyle?, heading: Double?) {
        let bullet = bus.lineBullet(style: style)
        let name = String(localized: "\(bullet.text) bus")
        self.init(
            id: Self.busID(bus.id),
            coordinate: bus.coordinate,
            bearing: heading,
            bullet: bullet,
            accessibilityLabel: heading.map { String(localized: "\(name), heading \(Self.compassPoint($0))") } ?? name
        )
    }

    /// The nearest of the eight compass points to a bearing, such as "northeast" for 40°.
    private static func compassPoint(_ bearing: Double) -> String {
        let points = [
            String(localized: "north"), String(localized: "northeast"), String(localized: "east"),
            String(localized: "southeast"), String(localized: "south"), String(localized: "southwest"),
            String(localized: "west"), String(localized: "northwest"),
        ]
        let index = Int((bearing / 45).rounded()) % points.count
        return points[(index + points.count) % points.count]
    }
}

extension View {
    /// Keeps `buses` refreshed while the app is in the foreground, from the environment's transit client and clock,
    /// and pauses it in the background.
    func liveBuses(_ buses: LiveBuses) -> some View {
        modifier(LiveBusesUpdates(buses: buses))
    }
}

private struct LiveBusesUpdates: ViewModifier {
    let buses: LiveBuses
    @Environment(\.transitClient) private var client
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .task(id: scenePhase == .active) {
                guard scenePhase == .active else { return }
                await buses.run(client: client) { [environment] in environment.now }
            }
    }
}
