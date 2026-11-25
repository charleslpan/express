import SwiftUI

/// The vehicles drawn on the map for the screen that owns them (``AppRouter/showVehicles(_:owner:)``).
struct MapVehicleLayer: Equatable {
    /// The screen the vehicles are for, such as `trip|<trip id>`.
    var owner: String
    var vehicles: [MapVehicle]
}

extension AppRouter {
    /// The vehicles on the map: only those of the journey or trip a screen is showing, none on the home map.
    var mapVehicles: [MapVehicle] {
        mapVehicleLayer?.vehicles ?? []
    }

    /// Draws `vehicles` on the map for `owner`, in place of any other screen's; none takes them off.
    func showVehicles(_ vehicles: [MapVehicle], owner: String) {
        guard !vehicles.isEmpty else {
            hideVehicles(owner: owner)
            return
        }
        let layer = MapVehicleLayer(owner: owner, vehicles: vehicles)
        if layer != mapVehicleLayer {
            mapVehicleLayer = layer
        }
    }

    /// Takes `owner`'s vehicles off the map; a newer screen's stay.
    func hideVehicles(owner: String) {
        if mapVehicleLayer?.owner == owner {
            mapVehicleLayer = nil
        }
    }
}

/// Follows `targets` for a screen and draws their vehicles on the map while it shows
/// (``AppRouter/showVehicles(_:owner:)``), pausing while the app is in the background or a sheet covers the screen.
private struct RideVehiclesTracking: ViewModifier {
    let owner: String
    let targets: [RideVehicles.Target]

    @State private var model = RideVehicles()
    @State private var isShowing = false
    @Environment(AppRouter.self) private var router
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.transitClient) private var client
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .task(id: isShowing && scenePhase == .active && router.sheet == nil) {
                guard isShowing, scenePhase == .active, router.sheet == nil else { return }
                await model.run(client: client) { [environment] in environment.now }
            }
            .onChange(of: targets, initial: true) { _, targets in
                model.track(targets)
            }
            .onChange(of: model.vehicles) { _, vehicles in
                if isShowing {
                    router.showVehicles(vehicles, owner: owner)
                }
            }
            .onAppear {
                isShowing = true
                router.showVehicles(model.vehicles, owner: owner)
            }
            .onDisappear {
                isShowing = false
                router.hideVehicles(owner: owner)
            }
    }
}

extension View {
    /// Shows the vehicles of `targets` on the map while this screen shows, for `owner`, which no other screen's
    /// vehicles replace until it goes. Pass none for nothing to follow.
    func rideVehicles(owner: String, targets: [RideVehicles.Target]) -> some View {
        modifier(RideVehiclesTracking(owner: owner, targets: targets))
    }
}
