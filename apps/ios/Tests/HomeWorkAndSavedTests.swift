import Foundation
import Testing
import TransitKit
@testable import Express

@MainActor
struct HomeWorkChipTests {
    @Test func chipsReadSetHomeAndSetWorkWhenNothingIsSet() {
        let chips = HomeWorkChip.chips(in: PlaceStore.inMemory())
        #expect(chips.map(\.slot) == [.home, .work])
        #expect(chips.map(\.title) == ["Set Home", "Set Work"])
        #expect(chips.map(\.isSet) == [false, false])
        #expect(chips.map(\.systemImage) == ["house", "briefcase"])
    }

    @Test func chipsShowTheirPlacesOnceSet() {
        let store = PlaceStore.inMemory()
        store.set(.home, to: place(1))
        store.set(.work, to: place(2))
        let chips = HomeWorkChip.chips(in: store)
        #expect(chips.map(\.title) == ["Home", "Work"])
        #expect(chips.map(\.place?.placeID) == ["place-1", "place-2"])
        #expect(chips.map(\.systemImage) == ["house.fill", "briefcase.fill"])
    }

    @Test func onlyTheSetChipChanges() {
        let store = PlaceStore.inMemory()
        store.set(.work, to: place(2))
        #expect(HomeWorkChip.chips(in: store).map(\.title) == ["Set Home", "Work"])
    }

    @Test func removingHomeTurnsItsChipBackToSetHome() {
        let store = PlaceStore.inMemory()
        store.set(.home, to: place(1))
        store.clear(.home)
        #expect(HomeWorkChip.chips(in: store).first?.title == "Set Home")
    }

    @Test func makingHomeYourWorkLeavesHomeUnset() {
        let store = PlaceStore.inMemory()
        store.set(.home, to: place(1))
        store.set(.work, to: place(1))
        #expect(HomeWorkChip.chips(in: store).map(\.title) == ["Set Home", "Work"])
    }

    @Test func aChipPlansToTheLiveDetailsFirst() {
        let store = PlaceStore.inMemory()
        store.set(.home, to: place(1))
        let home = HomeWorkChip.chips(in: store)[0]
        let destination = home.destination(details: place(1), cachedCoordinate: Coordinate(latitude: 0, longitude: 0))
        #expect(destination == place(1))
    }

    @Test func aChipFallsBackToTheCachedCoordinateUnderItsTitle() {
        let store = PlaceStore.inMemory()
        store.set(.work, to: place(2))
        let work = HomeWorkChip.chips(in: store)[1]
        let coordinate = Coordinate(latitude: 40.75, longitude: -73.98)
        let destination = work.destination(details: nil, cachedCoordinate: coordinate)
        #expect(destination == PlaceDetails(placeID: "place-2", name: "Work", coordinate: coordinate))
    }

    @Test func aChipWithNoPlaceOrNothingToPlanWithGoesNowhere() {
        let store = PlaceStore.inMemory()
        let unset = HomeWorkChip.chips(in: store)[0]
        #expect(unset.destination(details: place(1), cachedCoordinate: nil) == nil)
        store.set(.home, to: place(1))
        let home = HomeWorkChip.chips(in: store)[0]
        #expect(home.destination(details: nil, cachedCoordinate: nil) == nil)
    }
}

@MainActor
struct SavedPlacesListTests {
    private let clock = TestClock()

    @Test func savedPlacesListInTheOrderTheyWereSaved() {
        let store = makeStore()
        for number in [3, 1, 2] {
            store.save(place(number))
            clock.advance(by: 60)
        }
        #expect(SavedPlaceItem.items(in: store).map(\.placeID) == ["place-3", "place-1", "place-2"])
    }

    @Test func unsavingTakesARowOutAndSavingAgainPutsItLast() {
        let store = makeStore()
        for number in 1 ... 3 {
            store.save(place(number))
            clock.advance(by: 60)
        }
        store.unsave("place-1")
        #expect(SavedPlaceItem.items(in: store).map(\.placeID) == ["place-2", "place-3"])
        store.save(place(1))
        #expect(SavedPlaceItem.items(in: store).map(\.placeID) == ["place-2", "place-3", "place-1"])
    }

    @Test func homeAndWorkListOnlyWhereSaved() {
        let store = makeStore()
        store.set(.home, to: place(1))
        store.save(place(2))
        store.set(.work, to: place(2))
        #expect(SavedPlaceItem.items(in: store).map(\.placeID) == ["place-2"])
    }

    @Test func savingAgainKeepsAPlaceWhereItWas() {
        let store = makeStore()
        store.save(place(1))
        store.save(place(2))
        store.save(place(1), label: "Office")
        #expect(SavedPlaceItem.items(in: store).map(\.placeID) == ["place-1", "place-2"])
    }

    @Test func rowsShowYourLabelOverGooglesName() {
        let store = makeStore()
        store.save(place(1), label: "Mom's")
        store.save(place(2))
        let items = SavedPlaceItem.items(in: store)
        #expect(items.map(\.text.title) == ["Mom's", "Place 2"])
        #expect(items.map(\.text.isLoading) == [false, false])
    }

    @Test func aRowLoadsUntilItsDetailsArrive() {
        let store = makeStore()
        store.save(place(1))
        store.save(place(2))
        store.details.forget("place-2")
        let items = SavedPlaceItem.items(in: store)
        #expect(items.map(\.text.isLoading) == [false, true])
        #expect(items[1].text == RememberedPlaceText(entry: nil))
    }

    @Test func aRowWhoseDetailsFailedSaysSo() async {
        let store = makeStore()
        store.save(place(1))
        store.details.forget("place-1")
        // The store has no lookup, so the fetch fails.
        await store.details.load("place-1")
        let text = SavedPlaceItem.items(in: store)[0].text
        #expect(text.title == "Place unavailable")
        #expect(text.isLoading == false)
    }

    private func makeStore() -> PlaceStore {
        PlaceStore.inMemory(now: { [clock] in clock.now })
    }
}

private func place(_ number: Int) -> PlaceDetails {
    PlaceDetails(
        placeID: "place-\(number)",
        name: "Place \(number)",
        address: "\(number) Broadway, New York, NY, USA",
        coordinate: Coordinate(latitude: 40.7 + Double(number) / 1000, longitude: -74)
    )
}

/// A clock the tests move by hand.
@MainActor
private final class TestClock {
    var now = Date(timeIntervalSince1970: 1_793_748_600)

    func advance(by interval: TimeInterval) {
        now += interval
    }
}
