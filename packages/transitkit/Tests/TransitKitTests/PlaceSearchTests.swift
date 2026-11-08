import Foundation
import Testing
@testable import TransitKit

@MainActor
struct PlaceSearchDebounceTests {
    @Test func asksOnceTypingPauses() async {
        let clock = TestClock()
        let service = FakePlaceSearchService()
        let search = PlaceSearch(service: service, debounce: .milliseconds(300), clock: clock)

        search.update(query: "G")
        search.update(query: "Gr")
        search.update(query: "Grand")
        #expect(search.status == .loading)

        clock.advance(by: .milliseconds(299))
        #expect(await service.queries.isEmpty)

        clock.advance(by: .milliseconds(1))
        await search.searchTask?.value
        #expect(await service.queries == ["Grand"])
        #expect(search.status == .results(FakePlaceSearchService.grand))
    }

    @Test func eachPauseAsksForTheQueryAtThatMoment() async {
        let clock = TestClock()
        let service = FakePlaceSearchService()
        let search = PlaceSearch(service: service, debounce: .milliseconds(300), clock: clock)

        search.update(query: "Gr")
        clock.advance(by: .milliseconds(300))
        await search.searchTask?.value
        search.update(query: "Grand")
        clock.advance(by: .milliseconds(300))
        await search.searchTask?.value

        #expect(await service.queries == ["Gr", "Grand"])
    }

    @Test func keepsTheLastResultsWhileTheNextLoad() async {
        let clock = TestClock()
        let service = FakePlaceSearchService()
        let search = PlaceSearch(service: service, clock: clock)

        search.update(query: "Grand")
        clock.advance(by: .seconds(1))
        await search.searchTask?.value
        search.update(query: "Grand C")

        #expect(search.status == .results(FakePlaceSearchService.grand))
    }

    @Test func anEmptyQueryShowsTheHintWithoutAsking() async {
        let clock = TestClock()
        let service = FakePlaceSearchService()
        let search = PlaceSearch(service: service, clock: clock)

        search.update(query: "Grand")
        search.update(query: "   ")
        clock.advance(by: .seconds(1))
        await search.searchTask?.value

        #expect(search.status == .idle)
        #expect(await service.queries.isEmpty)
    }

    @Test func trimsTheQuery() async {
        let clock = TestClock()
        let service = FakePlaceSearchService()
        let search = PlaceSearch(service: service, clock: clock)

        search.update(query: "  Grand ")
        clock.advance(by: .seconds(1))
        await search.searchTask?.value

        #expect(await service.queries == ["Grand"])
    }

    @Test func asksWithinTheServiceArea() async {
        let clock = TestClock()
        let service = FakePlaceSearchService()
        let area = ServiceArea(south: 1, west: 2, north: 3, east: 4)
        let search = PlaceSearch(service: service, area: area, clock: clock)

        search.update(query: "Grand")
        clock.advance(by: .seconds(1))
        await search.searchTask?.value

        #expect(await service.areas == [area])
    }
}

@MainActor
struct PlaceSearchStatusTests {
    @Test func withoutAServiceSearchIsUnavailable() async {
        let search = PlaceSearch(service: nil)
        #expect(search.status == .unavailable)

        search.update(query: "Grand")
        #expect(search.status == .unavailable)
        #expect(search.session == nil)
        #expect(await search.pick(FakePlaceSearchService.grand[0]) == nil)
    }

    @Test func nothingFoundShowsNoResults() async {
        let clock = TestClock()
        let search = PlaceSearch(service: FakePlaceSearchService(), clock: clock)

        search.update(query: "zzzz")
        clock.advance(by: .seconds(1))
        await search.searchTask?.value

        #expect(search.status == .noResults)
    }

    @Test func aFailureShowsAndRetryAsksAgainAtOnce() async {
        let clock = TestClock()
        let service = FakePlaceSearchService(error: .offline)
        let search = PlaceSearch(service: service, clock: clock)

        search.update(query: "Grand")
        clock.advance(by: .seconds(1))
        await search.searchTask?.value
        #expect(search.status == .failed(.offline))

        await service.setError(nil)
        search.retry()
        #expect(search.status == .loading)
        await search.searchTask?.value

        #expect(search.status == .results(FakePlaceSearchService.grand))
        #expect(await service.queries == ["Grand", "Grand"])
    }

    @Test func anUnexpectedErrorCountsAsFailed() async {
        let clock = TestClock()
        let service = FakePlaceSearchService(error: nil, otherError: URLError(.badServerResponse))
        let search = PlaceSearch(service: service, clock: clock)

        search.update(query: "Grand")
        clock.advance(by: .seconds(1))
        await search.searchTask?.value

        #expect(search.status == .failed(.failed))
    }

    @Test func aFailedPickKeepsTheResultsAndSaysWhy() async {
        let clock = TestClock()
        let service = FakePlaceSearchService()
        let search = PlaceSearch(service: service, clock: clock)
        search.update(query: "Grand")
        clock.advance(by: .seconds(1))
        await search.searchTask?.value

        await service.setError(.offline)
        let picked = await search.pick(FakePlaceSearchService.grand[0])

        #expect(picked == nil)
        #expect(search.pickError == .offline)
        #expect(search.picking == nil)
        #expect(search.status == .results(FakePlaceSearchService.grand))
    }
}

@MainActor
struct PlaceSearchSessionTests {
    @Test func startsAtTheFirstKeystroke() {
        let search = PlaceSearch(service: FakePlaceSearchService(), clock: TestClock())
        #expect(search.session == nil)

        search.update(query: "G")
        #expect(search.session != nil)
    }

    @Test func everyKeystrokeAndThePickShareOneSession() async throws {
        let clock = TestClock()
        let service = FakePlaceSearchService()
        let search = PlaceSearch(service: service, clock: clock)

        search.update(query: "Gr")
        clock.advance(by: .seconds(1))
        await search.searchTask?.value
        search.update(query: "Grand")
        clock.advance(by: .seconds(1))
        await search.searchTask?.value
        let session = try #require(search.session)
        let picked = await search.pick(FakePlaceSearchService.grand[0])

        #expect(picked?.name == "Grand Central Terminal")
        #expect(await service.sessions == [session, session])
        #expect(await service.detailSessions == [session])
    }

    @Test func aPickEndsTheSessionAndTheNextSearchStartsANewOne() async throws {
        let clock = TestClock()
        let service = FakePlaceSearchService()
        let search = PlaceSearch(service: service, clock: clock)

        search.update(query: "Grand")
        clock.advance(by: .seconds(1))
        await search.searchTask?.value
        let first = try #require(search.session)
        _ = await search.pick(FakePlaceSearchService.grand[0])
        #expect(search.session == nil)

        search.update(query: "Grand Army")
        let second = try #require(search.session)
        #expect(second != first)
    }

    @Test func aFailedPickKeepsTheSessionForTheRetry() async throws {
        let clock = TestClock()
        let service = FakePlaceSearchService()
        let search = PlaceSearch(service: service, clock: clock)
        search.update(query: "Grand")
        clock.advance(by: .seconds(1))
        await search.searchTask?.value
        let session = try #require(search.session)

        await service.setError(.failed)
        _ = await search.pick(FakePlaceSearchService.grand[0])
        #expect(search.session == session)

        await service.setError(nil)
        _ = await search.pick(FakePlaceSearchService.grand[0])
        #expect(await service.detailSessions == [session, session])
        #expect(search.session == nil)
    }

    @Test func resetEndsTheSession() {
        let search = PlaceSearch(service: FakePlaceSearchService(), clock: TestClock())
        search.update(query: "Grand")

        search.reset()

        #expect(search.session == nil)
        #expect(search.query.isEmpty)
        #expect(search.status == .idle)
    }

    @Test func clearingTheQueryKeepsTheSession() throws {
        let search = PlaceSearch(service: FakePlaceSearchService(), clock: TestClock())
        search.update(query: "Grand")
        let session = try #require(search.session)

        search.update(query: "")
        search.update(query: "Union")

        #expect(search.session == session)
    }
}

struct PlaceMappingTests {
    @Test func suggestionTrimsItsText() {
        let suggestion = PlaceSuggestion(
            placeID: "gct",
            primaryText: " Grand Central Terminal ",
            secondaryText: "89 E 42nd St, New York, NY\n"
        )
        #expect(suggestion == PlaceSuggestion(
            placeID: "gct",
            title: "Grand Central Terminal",
            subtitle: "89 E 42nd St, New York, NY"
        ))
    }

    @Test func suggestionDropsAnEmptySubtitle() {
        let suggestion = PlaceSuggestion(placeID: "gct", primaryText: "Grand Central", secondaryText: "  ")
        #expect(suggestion?.subtitle == nil)
    }

    @Test(arguments: [("", "Grand Central"), ("gct", ""), ("gct", "   ")])
    func suggestionNeedsAnIDAndATitle(placeID: String, primaryText: String) {
        #expect(PlaceSuggestion(placeID: placeID, primaryText: primaryText, secondaryText: nil) == nil)
    }

    @Test func detailsTakeTheProvidersFields() {
        let details = PlaceDetails(
            placeID: "gct",
            name: "Grand Central Terminal",
            address: "89 E 42nd St, New York, NY 10017, USA",
            latitude: 40.7527,
            longitude: -73.9772
        )
        #expect(details == PlaceDetails(
            placeID: "gct",
            name: "Grand Central Terminal",
            address: "89 E 42nd St, New York, NY 10017, USA",
            coordinate: Coordinate(latitude: 40.7527, longitude: -73.9772)
        ))
    }

    @Test func detailsFallBackToTheSuggestion() {
        let suggestion = PlaceSuggestion(placeID: "gct", title: "Grand Central Terminal", subtitle: "Midtown")
        let details = PlaceDetails(
            placeID: "",
            name: " ",
            address: nil,
            latitude: 40.7527,
            longitude: -73.9772,
            suggestion: suggestion
        )
        #expect(details?.placeID == "gct")
        #expect(details?.name == "Grand Central Terminal")
        #expect(details?.address == "Midtown")
    }

    @Test func detailsDropAnAddressThatRepeatsTheName() {
        let details = PlaceDetails(
            placeID: "x",
            name: "350 5th Ave",
            address: "350 5th Ave",
            latitude: 40.7484,
            longitude: -73.9857
        )
        #expect(details?.address == nil)
    }

    @Test(arguments: [(-180.0, -180.0), (91.0, 0.0), (0.0, 181.0)])
    func detailsNeedARealCoordinate(latitude: Double, longitude: Double) {
        let details = PlaceDetails(placeID: "x", name: "X", address: nil, latitude: latitude, longitude: longitude)
        #expect(details == nil)
    }

    @Test func detailsNeedANameAndAnID() {
        #expect(PlaceDetails(placeID: "x", name: nil, address: nil, latitude: 0, longitude: 0) == nil)
        #expect(PlaceDetails(placeID: "", name: "X", address: nil, latitude: 0, longitude: 0) == nil)
    }
}
