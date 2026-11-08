import Foundation
import Observation
import os
import SwiftData
import TransitKit

/// A place Express remembers, as ``PlaceStore`` lists it: the Google place ID and Express's own data about it. Its
/// name and address come from ``PlaceStore/details`` (fetched live, never stored).
struct RememberedPlace: Identifiable, Hashable, Sendable {
    let placeID: String
    /// The user's own name for a saved place; nil for recents and unlabelled places.
    let label: String?
    /// When it was picked (recents) or saved (saved places, Home, Work).
    let date: Date
    /// Its cached coordinate while that's at most 30 days old, else nil (fetch the details again).
    let coordinate: Coordinate?

    var id: String {
        placeID
    }
}

/// The places you picked and saved, kept in SwiftData across launches: recents (newest first, at most
/// ``recentsLimit``, one per place), saved places in the order you saved them, and Home and Work, one each.
///
/// Inject it with `.environment(_:)` and read it as `@Environment(PlaceStore.self) private var places: PlaceStore?`.
/// It persists only place IDs, plus coordinates for at most 30 days (Google's terms; see `PlaceRecords.swift`); names
/// and addresses come live from ``details``. `ExpressApp` makes it with ``persistent(lookup:)``; the screenshot harness
/// and tests use ``inMemory(lookup:now:)``.
@MainActor
@Observable
final class PlaceStore {
    /// How many recents the store keeps; picking another drops the oldest.
    static let recentsLimit = 20

    /// Places picked in search, newest first.
    private(set) var recents: [RememberedPlace] = []
    /// Saved places, in the order they were saved.
    private(set) var saved: [RememberedPlace] = []
    private(set) var home: RememberedPlace?
    private(set) var work: RememberedPlace?

    /// The session's names, addresses, and coordinates, by place ID: fetched live and never stored.
    let details: PlaceDetailsCache

    private let container: ModelContainer
    private let context: ModelContext
    private let now: @MainActor () -> Date

    /// A store over `container`, fetching details through `lookup` (nil where the build has no Places key) and
    /// telling the time with `now`. It erases coordinates past their 30 days as it opens.
    init(
        container: ModelContainer,
        lookup: (any PlaceLookupService)? = nil,
        now: @escaping @MainActor () -> Date = { .now }
    ) {
        self.container = container
        context = container.mainContext
        self.now = now
        details = PlaceDetailsCache(lookup: lookup)
        details.onFetch = { [weak self] place in self?.refreshCoordinate(of: place) }
        eraseExpiredCoordinates()
        reload()
    }

    // MARK: - Recents

    /// Records `place` as picked at `date` (now, by default): first in ``recents`` where that's the newest, once,
    /// with its coordinate. Drops the oldest beyond ``recentsLimit``.
    func addRecent(_ place: PlaceDetails, pickedAt date: Date? = nil) {
        let date = date ?? now()
        details.remember(place)
        var records = fetch(RecentPlaceRecord.self)
        let matches = records.filter { $0.placeID == place.placeID }
        let record = matches.first ?? RecentPlaceRecord(placeID: place.placeID, pickedAt: date)
        if matches.isEmpty {
            context.insert(record)
            records.append(record)
        }
        for duplicate in matches.dropFirst() {
            context.delete(duplicate)
        }
        records.removeAll { $0.placeID == place.placeID && $0 !== record }
        record.pickedAt = date
        record.cache(place.coordinate, fetchedAt: now())
        for oldest in records.sorted(by: Self.newestFirst).dropFirst(Self.recentsLimit) {
            context.delete(oldest)
        }
        persist()
    }

    /// Forgets every recent.
    func clearRecents() {
        for record in fetch(RecentPlaceRecord.self) {
            context.delete(record)
        }
        persist()
    }

    // MARK: - Saved places

    func isSaved(_ placeID: String) -> Bool {
        saved.contains { $0.placeID == placeID }
    }

    /// Saves `place` at the end of ``saved`` (where it isn't already), with `label` where one is given.
    func save(_ place: PlaceDetails, label: String? = nil) {
        let record = savedRecord(for: place)
        if !record.isSaved {
            record.isSaved = true
            record.addedAt = now()
            record.sortOrder = (fetch(SavedPlaceRecord.self).map(\.sortOrder).max() ?? 0) + 1
        }
        if let label {
            let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            record.label = trimmed.isEmpty ? nil : trimmed
        }
        persist()
    }

    /// Takes the place out of ``saved``, with its label. It stays Home or Work where it is one.
    func unsave(_ placeID: String) {
        for record in fetch(SavedPlaceRecord.self) where record.placeID == placeID {
            record.isSaved = false
            record.label = nil
            deleteIfUnused(record)
        }
        persist()
    }

    // MARK: - Home and Work

    /// Which of Home and Work the place is, if either.
    func slot(of placeID: String) -> PlaceSlot? {
        if home?.placeID == placeID {
            return .home
        }
        return work?.placeID == placeID ? .work : nil
    }

    /// Makes `place` Home or Work, replacing the place that was. A place is one or the other: making Home your Work
    /// leaves you no Home.
    func set(_ slot: PlaceSlot, to place: PlaceDetails) {
        for record in fetch(SavedPlaceRecord.self) where record.slot == slot && record.placeID != place.placeID {
            record.slot = nil
            deleteIfUnused(record)
        }
        savedRecord(for: place).slot = slot
        persist()
    }

    /// Leaves Home or Work unset.
    func clear(_ slot: PlaceSlot) {
        for record in fetch(SavedPlaceRecord.self) where record.slot == slot {
            record.slot = nil
            deleteIfUnused(record)
        }
        persist()
    }

    // MARK: - Coordinates

    /// Replaces the cached coordinate of every record of `place` with its fresh one, such as after a live details
    /// fetch, restarting its 30 days.
    func refreshCoordinate(of place: PlaceDetails) {
        let date = now()
        var changed = false
        for record in fetch(RecentPlaceRecord.self) where record.placeID == place.placeID {
            record.cache(place.coordinate, fetchedAt: date)
            changed = true
        }
        for record in fetch(SavedPlaceRecord.self) where record.placeID == place.placeID {
            record.cache(place.coordinate, fetchedAt: date)
            changed = true
        }
        if changed {
            persist()
        }
    }

    /// The place's cached coordinate, the freshest of its records', while it's at most 30 days old; nil where there's
    /// none and the details must be fetched again (``PlaceDetailsCache/load(_:)`` caches the new one).
    func coordinate(for placeID: String) -> Coordinate? {
        let date = now()
        let recents: [any CoordinateCache] = fetch(RecentPlaceRecord.self).filter { $0.placeID == placeID }
        let saved: [any CoordinateCache] = fetch(SavedPlaceRecord.self).filter { $0.placeID == placeID }
        return (recents + saved)
            .max { ($0.coordinateFetchedAt ?? .distantPast) < ($1.coordinateFetchedAt ?? .distantPast) }?
            .coordinate(at: date)
    }

    /// Erases every coordinate older than 30 days, as Google's terms require.
    func eraseExpiredCoordinates() {
        let date = now()
        let erasedRecents = fetch(RecentPlaceRecord.self).map { $0.eraseExpiredCoordinate(at: date) }
        let erasedSaved = fetch(SavedPlaceRecord.self).map { $0.eraseExpiredCoordinate(at: date) }
        if (erasedRecents + erasedSaved).contains(true) {
            persist()
        }
    }

    /// The store's SwiftData context, for tests that check what's on disk.
    var modelContext: ModelContext {
        context
    }

    // MARK: - Storage

    /// Saves pending changes and republishes the lists.
    private func persist() {
        do {
            try context.save()
        } catch {
            Self.log.error("Couldn't save places: \(error.localizedDescription, privacy: .public)")
        }
        reload()
    }

    /// Republishes the lists from the store.
    private func reload() {
        let date = now()
        recents = fetch(RecentPlaceRecord.self)
            .sorted(by: Self.newestFirst)
            .map { $0.remembered(at: date) }
        let records = fetch(SavedPlaceRecord.self)
        saved = records
            .filter(\.isSaved)
            .sorted { ($0.sortOrder, $0.addedAt) < ($1.sortOrder, $1.addedAt) }
            .map { $0.remembered(at: date) }
        home = records.first { $0.slot == .home }?.remembered(at: date)
        work = records.first { $0.slot == .work }?.remembered(at: date)
    }

    /// The saved record for `place`, made where there's none, with the place's coordinate freshly cached.
    private func savedRecord(for place: PlaceDetails) -> SavedPlaceRecord {
        let date = now()
        let record = fetch(SavedPlaceRecord.self).first { $0.placeID == place.placeID } ?? {
            let record = SavedPlaceRecord(placeID: place.placeID, addedAt: date)
            context.insert(record)
            return record
        }()
        record.cache(place.coordinate, fetchedAt: date)
        details.remember(place)
        return record
    }

    /// Deletes a record that's neither saved nor Home or Work.
    private func deleteIfUnused(_ record: SavedPlaceRecord) {
        if !record.isSaved, record.slot == nil {
            context.delete(record)
        }
    }

    private func fetch<Record: PersistentModel>(_: Record.Type) -> [Record] {
        do {
            return try context.fetch(FetchDescriptor<Record>())
        } catch {
            Self.log.error("Couldn't read places: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private static func newestFirst(_ lhs: RecentPlaceRecord, _ rhs: RecentPlaceRecord) -> Bool {
        lhs.pickedAt == rhs.pickedAt ? lhs.placeID < rhs.placeID : lhs.pickedAt > rhs.pickedAt
    }

    private static let log = Logger(subsystem: "com.charleslpan.express", category: "places")
}

// MARK: - Containers

extension PlaceStore {
    /// The models the store keeps.
    static let schema = Schema([RecentPlaceRecord.self, SavedPlaceRecord.self])

    /// The app's store, on disk in Application Support (`Places.store`). Falls back to memory, so the app still
    /// works for the session, where the file can't be opened.
    static func persistent(lookup: (any PlaceLookupService)?) -> PlaceStore {
        do {
            let configuration = ModelConfiguration("Places", schema: schema)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            return PlaceStore(container: container, lookup: lookup)
        } catch {
            let reason = String(describing: error)
            log.error("Couldn't open the places store, so it's in memory: \(reason, privacy: .public)")
            return inMemory(lookup: lookup)
        }
    }

    /// A store that lives only as long as the process: the screenshot harness's and the previews'.
    static func inMemory(
        lookup: (any PlaceLookupService)? = nil,
        now: @escaping @MainActor () -> Date = { .now }
    ) -> PlaceStore {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            return PlaceStore(container: container, lookup: lookup, now: now)
        } catch {
            fatalError("Couldn't make an in-memory places store: \(error)")
        }
    }
}

private extension RecentPlaceRecord {
    func remembered(at date: Date) -> RememberedPlace {
        RememberedPlace(placeID: placeID, label: nil, date: pickedAt, coordinate: coordinate(at: date))
    }
}

private extension SavedPlaceRecord {
    func remembered(at date: Date) -> RememberedPlace {
        RememberedPlace(placeID: placeID, label: label, date: addedAt, coordinate: coordinate(at: date))
    }
}
