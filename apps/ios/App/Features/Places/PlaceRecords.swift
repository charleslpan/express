import Foundation
import SwiftData
import TransitKit

// What Express keeps of the places you pick and save, in SwiftData.
//
// Google's terms: of what the Places SDK returns, Express persists only the Google place ID, which it may keep
// indefinitely, and the place's coordinate, which it may cache for at most 30 days. Each record keeps the coordinate
// with the date it was fetched; `PlaceStore` hides a coordinate once it's older than ``CoordinateCache/maxAge`` and
// erases it from the store at launch, and a fresh details fetch replaces it. Names and addresses are never stored:
// they're fetched live by place ID and held in memory for the session (`PlaceDetailsCache`). Everything else on a
// record is Express's own: labels, Home and Work, timestamps, and sort order.

/// A place picked in search, one per place ID: ``PlaceStore`` lists them newest first and keeps the last
/// ``PlaceStore/recentsLimit``.
///
/// Persists only the Google place ID, plus a coordinate for at most 30 days (Google's terms; see the top of this
/// file). Never add a name, an address, or any other field from Google.
@Model
final class RecentPlaceRecord: CoordinateCache {
    /// The Google place ID.
    var placeID: String
    /// When the place was last picked.
    var pickedAt: Date
    var latitude: Double?
    var longitude: Double?
    var coordinateFetchedAt: Date?

    init(placeID: String, pickedAt: Date) {
        self.placeID = placeID
        self.pickedAt = pickedAt
        latitude = nil
        longitude = nil
        coordinateFetchedAt = nil
    }
}

/// A place you saved, set as Home or Work, or both, one per place ID. ``isSaved`` puts it in the Saved list; ``slot``
/// makes it Home or Work, which at most one record each holds. A record that is neither is deleted.
///
/// Persists only the Google place ID, plus a coordinate for at most 30 days (Google's terms; see the top of this
/// file). Never add a name, an address, or any other field from Google.
@Model
final class SavedPlaceRecord: CoordinateCache {
    /// The Google place ID.
    var placeID: String
    /// The user's own name for the place, such as "Mom's"; nil shows Google's name.
    var label: String?
    /// Whether the place is in the Saved list.
    var isSaved: Bool
    /// ``PlaceSlot``'s raw value where the place is Home or Work.
    var slotRawValue: String?
    /// When the place was saved, or set as Home or Work if it never was.
    var addedAt: Date
    /// Its position in the Saved list, ascending.
    var sortOrder: Int
    var latitude: Double?
    var longitude: Double?
    var coordinateFetchedAt: Date?

    init(placeID: String, addedAt: Date, isSaved: Bool = false, sortOrder: Int = 0) {
        self.placeID = placeID
        self.addedAt = addedAt
        self.isSaved = isSaved
        self.sortOrder = sortOrder
        label = nil
        slotRawValue = nil
        latitude = nil
        longitude = nil
        coordinateFetchedAt = nil
    }

    var slot: PlaceSlot? {
        get { slotRawValue.flatMap(PlaceSlot.init(rawValue:)) }
        set { slotRawValue = newValue?.rawValue }
    }
}

/// Home or Work: a special saved place, held by one place at a time.
enum PlaceSlot: String, CaseIterable, Identifiable, Sendable {
    case home
    case work

    var id: String {
        rawValue
    }
}

/// A record that caches a place's coordinate for at most ``maxAge`` (Google's terms allow 30 days).
protocol CoordinateCache: AnyObject {
    var latitude: Double? { get set }
    var longitude: Double? { get set }
    /// When the coordinate was fetched from Google.
    var coordinateFetchedAt: Date? { get set }
}

extension CoordinateCache {
    /// How long a coordinate from Google may be kept: 30 days.
    static var maxAge: TimeInterval {
        30 * 24 * 60 * 60
    }

    /// Keeps `coordinate`, fetched at `date`, replacing any older one.
    func cache(_ coordinate: Coordinate, fetchedAt date: Date) {
        latitude = coordinate.latitude
        longitude = coordinate.longitude
        coordinateFetchedAt = date
    }

    /// The cached coordinate, or nil where there's none or it's older than ``maxAge`` at `now`.
    func coordinate(at now: Date) -> Coordinate? {
        guard let latitude, let longitude, let fetchedAt = coordinateFetchedAt,
              now.timeIntervalSince(fetchedAt) <= Self.maxAge
        else { return nil }
        return Coordinate(latitude: latitude, longitude: longitude)
    }

    /// Erases the coordinate where it's older than ``maxAge`` at `now`; true where it did.
    @discardableResult
    func eraseExpiredCoordinate(at now: Date) -> Bool {
        guard coordinateFetchedAt != nil || latitude != nil, coordinate(at: now) == nil else { return false }
        latitude = nil
        longitude = nil
        coordinateFetchedAt = nil
        return true
    }
}
