import GlassUI
import SwiftUI
import TransitKit

/// Where the journey options screen starts in the screenshot harness: which option is selected, and whether the time
/// picker is open. Nil outside the harness.
struct JourneyOptionsSeed: Equatable {
    var selectedOption = 0
    var editsTime = false
}

extension EnvironmentValues {
    /// The screenshot harness's starting point for the journey options (``JourneyOptionsSeed``).
    @Entry var journeyOptionsSeed: JourneyOptionsSeed?
}

/// Journey options in the home sheet, pushed over the place's card (``AppRouter/showJourneys(to:)``): from, to, and
/// time controls, then MOTIS's options for the subway and buses, refreshed every 30 seconds while they show. The
/// selected option is drawn on the map; tapping one hands it to ``AppRouter/showJourneyDetail(_:)``.
///
/// It draws no glass: the system sheet it sits in is the glass. Choosing a start or an end swaps the list for place
/// search, and choosing a time for the time picker.
struct JourneyOptionsView: View {
    /// What the list gives way to while the rider changes the journey.
    private enum Editing: Equatable {
        case from
        case to
        case time
    }

    @Environment(AppRouter.self) private var router
    @Environment(LocationService.self) private var location
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.transitClient) private var client
    @Environment(\.journeyOptionsSeed) private var seed

    @State private var planner: JourneyPlanner
    @State private var editing: Editing?
    /// Bumped by Try Again, which restarts planning.
    @State private var attempt = 0
    @State private var isSeeded = false

    init(route: JourneyOptionsRoute) {
        _planner = State(initialValue: JourneyPlanner(query: route.query))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            switch editing {
            case .from, .to:
                PlaceSearchPanel(onPick: pick, onCancel: endEditing)
            case .time:
                ScrollView {
                    JourneyTimePicker(time: planner.query.time, now: environment.now) { time in
                        if let time {
                            planner.query.time = time
                        }
                        endEditing()
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.md)
                }
            case nil:
                list
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
        .onAppear(perform: start)
        .onChange(of: planner.options) { _, _ in
            select()
        }
        .onChange(of: planner.query) { _, _ in
            router.selectedJourney = nil
        }
    }

    /// The back button and title, which is what shows at the sheet's peek.
    private var header: some View {
        HStack(spacing: Spacing.sm) {
            Button("Back", systemImage: "chevron.left") {
                router.closeJourneys()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .accessibilityHint("Returns to the place")
            .accessibilityIdentifier("journeys.back")
            Text("Directions")
                .typography(.sectionTitle)
                .foregroundStyle(.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.lg)
        .padding(.bottom, Spacing.xs)
        // Past AX2 the header would outgrow the sheet's peek, which it has to fit.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                JourneyControls(
                    query: planner.query,
                    now: environment.now,
                    onChooseFrom: { choose(.from) },
                    onChooseTo: { choose(.to) },
                    onUseCurrentLocation: useCurrentLocation,
                    onSwap: { planner.query.swapEnds() },
                    onChooseTime: { editing = .time }
                )
                content
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.xs)
            .padding(.bottom, Spacing.md)
        }
        // Planning runs while the list shows, and starts again when the journey or the location changes.
        .task(id: PlanningKey(
            query: planner.query,
            authorization: location.authorization,
            hasLocation: location.location != nil,
            attempt: attempt
        )) {
            await planner.run(client: client, location: location) { [environment] in environment.now }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch planner.status {
        case .locating:
            progress("Finding your location…", id: "journeys.locating")
        case .loading:
            progress("Finding journeys…", id: "journeys.loading")
        case let .options(options):
            optionsList(options)
        case .noJourneys:
            JourneyStates.noJourneys {
                editing = .time
            }
        case .outsideServiceArea:
            // Starting from here, outside the city, the way on is a start inside it.
            JourneyStates.outsideServiceArea(
                onChooseStart: planner.query.needsCurrentLocation ? { choose(.from) } : nil
            )
        case let .locationOff(authorization):
            JourneyStates.locationOff(authorization) {
                choose(.from)
            }
        case let .failed(error):
            JourneyStates.failed(error) {
                attempt += 1
            }
        }
    }

    private func optionsList(_ options: [JourneyOption]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Checked every 10 seconds, so the notice comes up a minute after the last good refresh.
            TimelineView(.periodic(from: .now, by: 10)) { _ in
                let mayNotBeRealTime = planner.mayNotBeRealTime(at: environment.now)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    if mayNotBeRealTime {
                        MayNotBeRealTimeNotice()
                    }
                    ForEach(options) { option in
                        JourneyOptionRow(
                            summary: option.summary,
                            now: environment.now,
                            isSelected: router.selectedJourney?.id == option.id,
                            mayNotBeRealTime: mayNotBeRealTime,
                            alertFlag: option.itinerary.alertFlag
                        ) {
                            router.showJourneyDetail(option.itinerary, to: destinationName)
                        }
                    }
                }
            }
            Text("Times from the MTA, planned for the subway and buses.")
                .typography(.caption)
                .foregroundStyle(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Spacing.xs)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("journeys.list")
    }

    /// The journey's end as the rider named it, for its plan's last walk.
    private var destinationName: String? {
        if case let .place(place) = planner.query.to {
            return place.name
        }
        return nil
    }

    private func progress(_ title: LocalizedStringKey, id: String) -> some View {
        ProgressView(title)
            .typography(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, Spacing.xl)
            .accessibilityIdentifier(id)
    }

    /// Asks for the location if the journey needs it, and opens where the harness says.
    private func start() {
        if planner.query.needsCurrentLocation, location.authorization != .denied,
           location.authorization != .restricted
        {
            location.requestLocation()
        }
        if let seed, !isSeeded, seed.editsTime {
            editing = .time
        }
    }

    /// Draws the selected option after the options change: the harness's pick the first time, then the rider's.
    private func select() {
        if let seed, !isSeeded, !planner.options.isEmpty {
            isSeeded = true
            let index = min(seed.selectedOption, planner.options.count - 1)
            router.selectedJourney = planner.options[index].itinerary
            return
        }
        router.selectedJourney = planner.selection(keeping: router.selectedJourney)
    }

    private func choose(_ end: Editing) {
        editing = end
        router.homeDetent = .full
    }

    private func pick(_ place: PlaceDetails) {
        if editing == .to {
            planner.query.to = .place(place)
        } else {
            planner.query.from = .place(place)
        }
        endEditing()
    }

    private func useCurrentLocation(for end: JourneyControls.End) {
        switch end {
        case .from: planner.query.from = .currentLocation
        case .to: planner.query.to = .currentLocation
        }
        location.requestLocation()
    }

    private func endEditing() {
        editing = nil
        router.homeDetent = .half
    }
}

/// What restarts planning: a new journey, a change in location permission, the first fix, or Try Again.
private struct PlanningKey: Hashable {
    var query: JourneyQuery
    var authorization: LocationService.Authorization
    var hasLocation: Bool
    var attempt: Int
}

/// The NYC layer's notice that times may not be real time, which the MTA's terms require once data is more than a
/// minute old. A filled panel rather than glass, since it sits in the sheet's glass.
struct MayNotBeRealTimeNotice: View {
    var identifier = "journeys.may-not-be-real-time"

    @ScaledMetric(relativeTo: .subheadline) private var gap = Spacing.xs

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: gap) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .foregroundStyle(.statusDelayed)
            Text("Times may not be real time. Express will keep trying to update them.")
                .foregroundStyle(.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .typography(.secondary)
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.tertiary, in: Radius.shape(Radius.sm))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}
