import Foundation
import GoogleMaps
import GooglePlaces

/// Hands the Google Maps Platform key to the Maps and Places SDKs, once, at launch.
///
/// The key is `GMSApiKey` in Info.plist, filled from `GOOGLE_MAPS_IOS_API_KEY` in the git-ignored
/// `Config/Secrets.xcconfig` (see `Config/Express.xcconfig`). Without one, ``isConfigured`` stays false and
/// ``MapView`` shows "Map unavailable" instead of a blank Google map.
@MainActor
enum GoogleMapsServices {
    /// Whether the SDKs have a key, so a map can load.
    private(set) static var isConfigured = false

    /// Provides the key from `bundle` to the SDKs, if it has one. Safe to call more than once.
    static func configure(bundle: Bundle = .main) {
        guard !isConfigured, let key = apiKey(in: bundle) else { return }
        isConfigured = GMSServices.provideAPIKey(key)
        GMSPlacesClient.provideAPIKey(key)
    }

    /// The key in `bundle`'s Info.plist, or nil where it is empty or the build setting never expanded.
    static func apiKey(in bundle: Bundle) -> String? {
        let key = (bundle.object(forInfoDictionaryKey: "GMSApiKey") as? String)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return key.isEmpty || key.hasPrefix("$(") ? nil : key
    }
}
