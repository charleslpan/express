import Foundation
import SwiftData
import Testing
import TransitKit
@testable import Express

@MainActor
struct PlaceStoreTests {
    private let clock = TestClock()

    // MARK: - Recents

    @Test func recentsListNewestFirst() {
        let store = makeStore()
        store.addRecent(place(1))
        clock.advance(by: 60)
        store.addRecent(place(2))
        #expect(store.recents.map(\.placeID) == ["place-2", "place-1"])
    }

    @Test func pickingARecentAgainMovesItToTheTopOnce() {
        let store = makeStore()
        for number in 1 ... 3 {
            store.addRecent(place(number))
            clock.advance(by: 60)
        }
        store.addRecent(place(1))
        #expect(store.recents.map(\.placeID) == ["place-1", "place-3", "place-2"])
    }

    @Test func recentsKeepOnlyTheNewest() {
        let store = makeStore()
        for number in 1 ... PlaceStore.recentsLimit + 5 {
            store.addRecent(place(number))
            clock.advance(by: 60)
        }
        #expect(store.recents.count == PlaceStore.recentsLimit)
        #expect(store.recents.first?.placeID == "place-\(PlaceStore.recentsLimit + 5)")
        #expect(store.recents.last?.placeID == "place-6")
        #expect(records(RecentPlaceRecord.self, in: store).count == PlaceStore.recentsLimit)
    }

    @Test func clearRecentsForgetsThemAll() {
        let store = makeStore()
        store.addRecent(place(1))
        store.addRecent(place(2))
        store.clearRecents()
        #expect(store.recents.isEmpty)
        #expect(records(RecentPlaceRecord.self, in: store).isEmpty)
    }

    // MARK: - Saved places

    @Test func saveAndUnsave() {
        let store = makeStore()
        store.save(place(1))
        clock.advance(by: 60)
        store.save(place(2), label: "  Mom's  ")
        #expect(store.saved.map(\.placeID) == ["place-1", "place-2"])
        #expect(store.saved.last?.label == "Mom's")
        #expect(store.isSaved("place-1"))

        store.unsave("place-1")
        #expect(!store.isSaved("place-1"))
        #expect(store.saved.map(\.placeID) == ["place-2"])
        #expect(records(SavedPlaceRecord.self, in: store).map(\.placeID) == ["place-2"])
    }

    @Test func savingTwiceKeepsOnePlaceInItsSpot() {
        let store = makeStore()
        store.save(place(1))
        store.save(place(2))
        store.save(place(1))
        #expect(store.saved.map(\.placeID) == ["place-1", "place-2"])
    }

    // MARK: - Home and Work

    @Test func homeAndWorkHoldOnePlaceEach() {
        let store = makeStore()
        store.set(.home, to: place(1))
        store.set(.work, to: place(2))
        store.set(.home, to: place(3))
        #expect(store.home?.placeID == "place-3")
        #expect(store.work?.placeID == "place-2")
        #expect(store.slot(of: "place-1") == nil)
        // place-1 was only Home, so nothing of it is left.
        #expect(!records(SavedPlaceRecord.self, in: store).contains { $0.placeID == "place-1" })
    }

    @Test func makingHomeYourWorkLeavesNoHome() {
        let store = makeStore()
        store.set(.home, to: place(1))
        store.set(.work, to: place(1))
        #expect(store.home == nil)
        #expect(store.work?.placeID == "place-1")
    }

    @Test func homeIsNotASavedPlaceAndSurvivesUnsaving() {
        let store = makeStore()
        store.set(.home, to: place(1))
        #expect(!store.isSaved("place-1"))
        store.save(place(1))
        store.unsave("place-1")
        #expect(store.home?.placeID == "place-1")
        store.clear(.home)
        #expect(store.home == nil)
        #expect(records(SavedPlaceRecord.self, in: store).isEmpty)
    }

    // MARK: - Coordinates (Google's 30 days)

    @Test func coordinatesExpireAfterThirtyDays() {
        let store = makeStore()
        store.addRecent(place(1))
        store.save(place(2))
        clock.advance(by: thirtyDays)
        #expect(store.coordinate(for: "place-1") == place(1).coordinate)
        clock.advance(by: 1)
        #expect(store.coordinate(for: "place-1") == nil)
        #expect(store.coordinate(for: "place-2") == nil)
    }

    @Test func openingTheStoreErasesExpiredCoordinates() {
        let container = makeContainer()
        let store = PlaceStore(container: container, now: { [clock] in clock.now })
        store.addRecent(place(1))
        store.set(.work, to: place(2))
        clock.advance(by: thirtyDays + 1)

        let reopened = PlaceStore(container: container, now: { [clock] in clock.now })
        let caches: [any CoordinateCache] = records(RecentPlaceRecord.self, in: reopened)
            + records(SavedPlaceRecord.self, in: reopened)
        #expect(caches.count == 2)
        #expect(caches.allSatisfy { $0.latitude == nil && $0.longitude == nil && $0.coordinateFetchedAt == nil })
        #expect(reopened.recents.first?.coordinate == nil)
        #expect(reopened.work?.coordinate == nil)
    }

    @Test func fetchingDetailsAgainRefreshesTheCoordinate() async {
        let moved = PlaceDetails(
            placeID: "place-1",
            name: "Place 1",
            coordinate: Coordinate(latitude: 40.75, longitude: -73.98)
        )
        let container = makeContainer()
        PlaceStore(container: container, now: { [clock] in clock.now }).addRecent(place(1))
        clock.advance(by: thirtyDays + 1)
        // The next launch: its details cache starts empty, so the place is fetched again.
        let store = PlaceStore(container: container, lookup: StubLookup(place: moved), now: { [clock] in clock.now })
        #expect(store.coordinate(for: "place-1") == nil)

        let details = await store.details.load("place-1")
        #expect(details == moved)
        #expect(store.coordinate(for: "place-1") == moved.coordinate)
        #expect(records(RecentPlaceRecord.self, in: store).first?.coordinateFetchedAt == clock.now)
    }

    // MARK: - Relaunch

    @Test func placesSurviveARelaunch() throws {
        let url = URL.temporaryDirectory.appending(path: "Places-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let store = try PlaceStore(container: onDisk(at: url), now: { [clock] in clock.now })
            store.addRecent(place(1))
            store.save(place(2), label: "Gym")
            store.set(.home, to: place(3))
        }
        let relaunched = try PlaceStore(container: onDisk(at: url), now: { [clock] in clock.now })
        #expect(relaunched.recents.map(\.placeID) == ["place-1"])
        #expect(relaunched.saved.map(\.placeID) == ["place-2"])
        #expect(relaunched.saved.first?.label == "Gym")
        #expect(relaunched.home?.placeID == "place-3")
        #expect(relaunched.recents.first?.coordinate == place(1).coordinate)
    }

    // MARK: - Helpers

    private let thirtyDays: TimeInterval = 30 * 24 * 60 * 60

    private func makeStore() -> PlaceStore {
        PlaceStore(container: makeContainer(), now: { [clock] in clock.now })
    }

    private func makeContainer() -> ModelContainer {
        let configuration = ModelConfiguration(schema: PlaceStore.schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: PlaceStore.schema, configurations: [configuration])
        } catch {
            fatalError("Couldn't make an in-memory container: \(error)")
        }
    }

    private func onDisk(at url: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: PlaceStore.schema, url: url)
        return try ModelContainer(for: PlaceStore.schema, configurations: [configuration])
    }

    private func records<Record: PersistentModel>(_: Record.Type, in store: PlaceStore) -> [Record] {
        (try? store.modelContext.fetch(FetchDescriptor<Record>())) ?? []
    }

    private func place(_ number: Int) -> PlaceDetails {
        PlaceDetails(
            placeID: "place-\(number)",
            name: "Place \(number)",
            coordinate: Coordinate(latitude: 40.7 + Double(number) / 1000, longitude: -74)
        )
    }
}

/// A clock the tests move by hand.
@MainActor
private final class TestClock {
    var now = Date(timeIntervalSince1970: 1_793_748_600)

    func advance(by interval: TimeInterval) {
        now += interval
    }
}

/// Looks every place up as `place`.
private struct StubLookup: PlaceLookupService {
    let place: PlaceDetails

    func details(forPlaceID _: String) async throws -> PlaceDetails {
        place
    }
}
