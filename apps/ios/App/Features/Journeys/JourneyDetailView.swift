import GlassUI
import SwiftUI
import TransitKit

/// Where the journey detail screen starts in the screenshot harness: whether each ride's stops between show unfolded.
/// Nil outside the harness.
struct JourneyDetailSeed: Equatable {
    var showsStops = false
}

extension EnvironmentValues {
    /// The screenshot harness's starting point for a journey's plan (``JourneyDetailSeed``).
    @Entry var journeyDetailSeed: JourneyDetailSeed?
}

/// A journey step by step, pushed in the home sheet over its options (``AppRouter/showJourneyDetail(_:to:)``): when it
/// leaves and arrives, then each walk, ride, and transfer in order, with live times, delays, and the stops between.
///
/// It refreshes the rides from their trips about every 30 seconds while it shows and the app is active, says when its
/// times may not be real time, and says plainly when a ride is cancelled or a connection can no longer be made. The
/// whole journey is drawn on the map; tapping a step zooms the map to it, and tapping a ride's line opens its trip
/// (``AppRouter/showTrip(_:)``). It draws no glass: the system sheet it sits in is the glass.
struct JourneyDetailView: View {
    let route: JourneyDetailRoute

    @Environment(AppRouter.self) private var router
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.transitClient) private var client
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.journeyDetailSeed) private var seed

    @State private var model: JourneyDetailModel

    init(route: JourneyDetailRoute) {
        self.route = route
        _model = State(initialValue: JourneyDetailModel(itinerary: route.itinerary))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                // Checked every 10 seconds, so the notice comes up a minute after the last good refresh.
                TimelineView(.periodic(from: .now, by: 10)) { _ in
                    content(mayNotBeRealTime: model.mayNotBeRealTime(at: environment.now))
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.xs)
                .padding(.bottom, Spacing.md)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
        // Refreshing runs while the app is active and the About sheet doesn't cover the plan.
        .task(id: scenePhase == .active && router.sheet == nil) {
            guard scenePhase == .active, router.sheet == nil else { return }
            await model.run(client: client) { [environment] in environment.now }
        }
        .onChange(of: model.itinerary) { _, itinerary in
            // The map follows the latest times; the same id leaves it where the rider put it.
            if router.selectedJourney?.id == itinerary.id {
                router.selectedJourney = itinerary
            }
        }
        .onAppear {
            if router.selectedJourney?.id != model.itinerary.id {
                router.selectedJourney = model.itinerary
            }
        }
        .onDisappear {
            router.showJourneyLegs([])
        }
    }

    /// The back button and title, which is what shows at the sheet's peek.
    private var header: some View {
        HStack(spacing: Spacing.sm) {
            Button("Back", systemImage: "chevron.left") {
                router.closeJourneyDetail()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .accessibilityHint("Returns to the journey options")
            .accessibilityIdentifier("journey.back")
            Text(route.destination.map { String(localized: "To \($0)") } ?? String(localized: "Journey"))
                .typography(.sectionTitle)
                .foregroundStyle(.textPrimary)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.lg)
        .padding(.bottom, Spacing.xs)
        // Past AX2 the header would outgrow the sheet's peek, which it has to fit.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private func content(mayNotBeRealTime: Bool) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            JourneyDetailSummary(summary: model.plan.summary)
                .contentShape(Rectangle())
                .onTapGesture {
                    router.showJourneyLegs([])
                }
                .accessibilityAction(named: "Show Whole Journey on Map") {
                    router.showJourneyLegs([])
                }
            if let problem = model.plan.problem {
                JourneyProblemNotice(problem: problem) {
                    router.closeJourneyDetail()
                }
            }
            if mayNotBeRealTime {
                MayNotBeRealTimeNotice(identifier: "journey.may-not-be-real-time")
            }
            ForEach(model.plan.steps) { step in
                stepView(step, realtimeIsStale: mayNotBeRealTime)
            }
            Text("Live times from the MTA. Tap a step to see it on the map.")
                .typography(.caption)
                .foregroundStyle(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Spacing.xs)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(model.hasRefreshed ? "journey.loaded" : "journey.loading")
    }

    @ViewBuilder
    private func stepView(_ step: JourneyStep, realtimeIsStale: Bool) -> some View {
        switch step {
        case let .walk(walk):
            JourneyWalkCard(walk: walk, leg: leg(walk.legIndex), destination: route.destination)
                .modifier(MapFocus(legs: step.legIndices))
        case let .ride(ride):
            JourneyRideCard(
                ride: ride,
                leg: leg(ride.legIndex),
                realtimeIsStale: realtimeIsStale,
                showsStops: seed?.showsStops ?? false
            ) {
                router.showTrip(TripRoute(tripId: ride.tripId, stationId: ride.board.stopId))
            }
            .modifier(MapFocus(legs: step.legIndices))
        case let .transfer(transfer):
            JourneyTransferRow(transfer: transfer)
                .modifier(MapFocus(legs: step.legIndices))
        }
    }

    private func leg(_ index: Int) -> Leg {
        model.itinerary.legs[index]
    }
}

/// Zooms the map to a step's legs when it's tapped, outlining the step while the map shows it alone.
private struct MapFocus: ViewModifier {
    let legs: [Int]

    @Environment(AppRouter.self) private var router

    func body(content: Content) -> some View {
        let isFocused = !legs.isEmpty && router.focusedJourneyLegs == legs
        content
            .overlay {
                if isFocused {
                    Radius.shape(Radius.md).strokeBorder(Color.brand, lineWidth: 2)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !legs.isEmpty else { return }
                router.showJourneyLegs(isFocused ? [] : legs)
                if router.homeDetent == .full {
                    router.homeDetent = .half
                }
            }
            .accessibilityAction(named: isFocused ? "Show Whole Journey on Map" : "Show on Map") {
                router.showJourneyLegs(isFocused ? [] : legs)
            }
            .accessibilityAddTraits(isFocused ? .isSelected : [])
    }
}
