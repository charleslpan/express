import CoreLocation
import Observation
import TransitKit

/// The user's location, over Core Location.
///
/// It asks for When In Use permission only when a screen needs the location (``requestLocation()``), never at launch.
/// Read ``authorization`` to choose between asking, showing the location, and the friendly denied state
/// (``LocationDeniedView``). Inject the app's one service with `.environment(_:)` and read it with
/// `@Environment(LocationService.self)`.
@MainActor
@Observable
final class LocationService: NSObject {
    /// Whether Express may use the location.
    enum Authorization: Equatable {
        /// Not asked yet; ``LocationService/requestLocation()`` asks.
        case notDetermined
        /// Turned off for Express, or for the whole device, in Settings.
        case denied
        /// Blocked by a device policy, such as Screen Time, which the user may not be able to change.
        case restricted
        case authorized
    }

    private(set) var authorization: Authorization
    /// The latest location, once authorized and updating.
    private(set) var location: Coordinate?

    private let manager: CLLocationManager?
    private var updates: Task<Void, Never>?

    /// Whether this is the live service over Core Location, rather than one fixed for the screenshot harness or
    /// previews. A fixed service's permission is pretend, so views keep the map's own location dot (which asks
    /// Core Location) off for it.
    var isLive: Bool {
        manager != nil
    }

    /// The live service, reading the current permission without asking for it.
    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        authorization = Authorization(manager.authorizationStatus)
        super.init()
        manager.delegate = self
    }

    /// A service fixed at `authorization` and `location` that never touches Core Location, for the screenshot
    /// harness and previews.
    init(fixed authorization: Authorization, location: Coordinate? = nil) {
        manager = nil
        self.authorization = authorization
        self.location = location
        super.init()
    }

    /// Asks for When In Use permission if it hasn't been asked yet, and starts updating ``location`` once it's
    /// granted. Call it when the user does something that needs the location, such as tapping "Show my location".
    func requestLocation() {
        guard let manager else { return }
        switch authorization {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorized: startUpdating()
        case .denied, .restricted: break
        }
    }

    /// Stops updating ``location``, such as when the screen that needs it goes away.
    func stopUpdating() {
        updates?.cancel()
        updates = nil
    }

    private func startUpdating() {
        guard manager != nil, updates == nil else { return }
        updates = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates() {
                    guard let self, !Task.isCancelled else { return }
                    if let location = update.location {
                        self.location = Coordinate(
                            latitude: location.coordinate.latitude,
                            longitude: location.coordinate.longitude
                        )
                    }
                }
            } catch {
                // The updates ended (cancelled or failed); the last location stands.
            }
        }
    }
}

extension LocationService: @preconcurrency CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let wasAsking = authorization == .notDetermined
        authorization = Authorization(manager.authorizationStatus)
        switch authorization {
        case .authorized where wasAsking: startUpdating()
        case .denied, .restricted: stopUpdating()
        default: break
        }
    }
}

private extension LocationService.Authorization {
    init(_ status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .restricted: self = .restricted
        case .denied: self = .denied
        case .authorizedAlways, .authorizedWhenInUse: self = .authorized
        @unknown default: self = .denied
        }
    }
}
