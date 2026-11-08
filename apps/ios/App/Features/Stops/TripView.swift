import GlassUI
import SwiftUI
import TransitKit

/// One vehicle's trip, pushed in the home sheet (``AppRouter/showTrip(_:)``): its line and headsign, where the
/// vehicle is now, then every stop it calls at with live arrival times and delays, the stops already passed greyed
/// out, and the vehicle drawn between the two it runs between. The trip's track shows on the map above, in the line's
/// colour, for as long as the view does (``AppRouter/showOnMap(_:)``).
///
/// The subway has no GPS, so the vehicle's place comes from its live times, as the map's trains do. It refreshes
/// about every 30 seconds while it shows and the app is active, and says plainly when the trip has ended, can't be
/// found, or can't be fetched.
struct TripView: View {
    let route: TripRoute

    @State private var model = TripModel()
    /// Bumped by "Try Again", which restarts refreshing.
    @State private var attempt = 0
    /// Whether the list has scrolled to the vehicle, which it does once, when the trip first loads.
    @State private var hasScrolledToVehicle = false
    @Environment(AppRouter.self) private var router
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.transitClient) private var transitClient
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    content(proxy: proxy)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("trip.\(state.identifier)")
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: refresh) {
            guard refresh.isActive else { return }
            await model.run(client: transitClient, tripId: route.tripId, now: { environment.now })
        }
        .onChange(of: mapTrip, initial: true) { _, trip in
            if let trip {
                router.showOnMap(trip)
            }
        }
        .onDisappear {
            router.hideOnMap(tripId: route.tripId)
        }
    }

    @ViewBuilder
    private func content(proxy: ScrollViewProxy) -> some View {
        switch state {
        case .loading:
            ProgressView("Loading this trip")
                .frame(maxWidth: .infinity, minHeight: 120)
        case let .failed(error):
            StopsFailureMessage(error: error, subject: "This trip") {
                attempt += 1
            }
        case .notFound:
            StopsMessage(
                "Trip Not Found",
                systemImage: "questionmark.circle",
                message: Text("This trip isn't running any more, or its times have changed. Go back for the latest.")
            )
        case let .loaded(trip, progress, realtimeIsStale):
            TripHeader(trip: trip, progress: progress, now: model.now)
            if progress.phase == .ended {
                StopsMessage(
                    "This Trip Has Ended",
                    systemImage: "flag.checkered",
                    message: endedMessage(progress)
                )
            }
            if realtimeIsStale, progress.phase != .ended {
                StopsNotRealTimeNotice(identifier: "trip.not-real-time")
            }
            TripStopList(
                progress: progress,
                bullet: trip.tripLeg?.lineBullet,
                mode: trip.tripLeg?.mode ?? .subway,
                stationId: route.stationId,
                realtimeIsStale: realtimeIsStale
            )
            .onAppear {
                guard !hasScrolledToVehicle else { return }
                hasScrolledToVehicle = true
                proxy.scrollTo(TripStopList.focusID(progress), anchor: .center)
            }
        }
    }

    private func endedMessage(_ progress: TripProgress) -> Text {
        guard let last = progress.stops.last, let time = last.time else {
            return Text("It has reached the end of the line.")
        }
        return Text("It reached \(last.name) at \(time, format: .stationClock).")
    }

    private var state: TripState {
        switch model.content {
        case .idle, .loading: return .loading
        case let .failed(error): return error.isNotFound ? .notFound : .failed(error)
        case let .loaded(trip, _, _):
            let progress = TripProgress(trip: trip, at: model.now)
            guard !progress.stops.isEmpty else { return .notFound }
            return .loaded(trip, progress, realtimeIsStale: model.content.mayNotBeRealTime(at: model.now))
        }
    }

    private var title: String {
        guard case let .loaded(trip, _, _) = model.content, let leg = trip.tripLeg else {
            return String(localized: "Trip")
        }
        let line = leg.lineBullet.map { TransitLine(bullet: $0, mode: leg.mode).name } ?? ""
        return leg.headsign.map { String(localized: "\(line) to \($0)") } ?? line
    }

    /// The trip's track for the map, in the line's colour, looking at the vehicle (or the next stop).
    private var mapTrip: MapTrip? {
        guard case let .loaded(trip, progress, _) = state else { return nil }
        let path = progress.path.count >= 2 ? progress.path : progress.stops.map(\.place.coordinate)
        guard path.count >= 2, let focus = progress.vehicle?.coordinate ?? progress.nextStop?.place.coordinate
            ?? progress.stops.last?.place.coordinate
        else { return nil }
        let color = trip.tripLeg?.lineBullet?.color.map { LineColor($0).color } ?? LineColor.unknownLine.color
        return MapTrip(line: MapPolyline(id: route.tripId, coordinates: path, color: color), focus: focus)
    }

    /// Refreshing runs while the app is active and the About sheet doesn't cover the trip.
    private var refresh: StopsRefreshKey {
        StopsRefreshKey(isActive: scenePhase == .active && router.sheet == nil, attempt: attempt)
    }
}

/// What the trip view shows.
private enum TripState: Equatable {
    case loading
    case loaded(Itinerary, TripProgress, realtimeIsStale: Bool)
    case notFound
    case failed(TransitError)

    /// The suffix of the content's accessibility identifier (`trip.loaded`), which the screenshot harness waits on.
    var identifier: String {
        switch self {
        case .loading: "loading"
        case let .loaded(_, progress, _): progress.phase == .ended ? "ended" : "loaded"
        case .notFound: "not-found"
        case .failed: "failed"
        }
    }
}

/// The trip's line and headsign, and where the vehicle is: "Between Bleecker St and Astor Pl", with the next stop
/// and when it gets there.
private struct TripHeader: View {
    let trip: Itinerary
    let progress: TripProgress
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                if let leg = trip.tripLeg, let bullet = leg.lineBullet {
                    LinePill(TransitLine(bullet: bullet, mode: leg.mode))
                }
                Text(headsign)
                    .typography(.sectionTitle)
                    .foregroundStyle(.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(lineLabel)
            .accessibilityAddTraits(.isHeader)
            if let whereNow {
                Text(whereNow)
                    .typography(.bodyEmphasized)
                    .foregroundStyle(.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let next {
                Text(next)
                    .typography(.secondary)
                    .foregroundStyle(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headsign: String {
        trip.tripLeg?.headsign.map { String(localized: "to \($0)") } ?? String(localized: "Trip")
    }

    private var lineLabel: String {
        guard let leg = trip.tripLeg, let bullet = leg.lineBullet else { return headsign }
        return "\(TransitLine(bullet: bullet, mode: leg.mode).accessibilityName) \(headsign)"
    }

    /// Where the vehicle is, as far as its live times say.
    private var whereNow: String? {
        switch progress.phase {
        case .notStarted:
            guard let first = progress.stops.first, let time = first.leaveTime else { return nil }
            return String(localized: "Leaves \(first.name) at \(time.formatted(.stationClock))")
        case .ended:
            return nil
        case .running:
            guard let vehicle = progress.vehicle else { return nil }
            let from = progress.stops[vehicle.fromIndex].name
            let to = progress.stops[vehicle.toIndex].name
            return vehicle.isAtStop
                ? String(localized: "Now at \(from)")
                : String(localized: "Now between \(from) and \(to)")
        }
    }

    /// The next stop and how soon, for a running trip: "Next: 14 St-Union Sq in 3 min · estimated position".
    private var next: String? {
        guard progress.phase == .running, let stop = progress.nextStop, let time = stop.time,
              progress.vehicle?.isAtStop != true
        else { return nil }
        let minutes = Int((time.timeIntervalSince(now) / 60).rounded(.up))
        let countdown = CountdownFormat.string(minutes: minutes)
        return String(localized: "Next: \(stop.name), \(countdown) · Position estimated from live times")
    }
}
