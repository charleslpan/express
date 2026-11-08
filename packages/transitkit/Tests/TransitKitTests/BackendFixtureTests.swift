import Foundation
import Testing
@testable import TransitKit

/// Checks that the fixtures recorded from Transitous still describe what Express's own server answers:
/// the same API (a response from production decodes through the same client) and the same dataset ids.
struct BackendFixtureTests {
    /// The datasets `apps/api/motis/config.yml` serves, named as Transitous names them.
    static let backendDatasets: Set = [
        "us-ny-MTA-NYCSubway",
        "us-ny-MTA-BusBronx",
        "us-ny-MTA-BusBrooklyn",
        "us-ny-MTA-BusManhattan",
        "us-ny-MTA-BusQueens",
        "us-ny-MTA-BusStatenIsland",
        "us-ny-MTA-BusCompany",
    ]

    /// Red Hook to Times Square, recorded from https://express-server-cyan-zeta.vercel.app on 2026-11-03.
    @Test func productionResponseDecodes() async throws {
        let client = try TransitClient(transport: FixtureTransport(fixture: "plan-red-hook-to-times-square-express"))
        let request = PlanRequest(
            from: .coordinate(Coordinate(latitude: 40.6757, longitude: -74.0086)),
            to: .coordinate(Coordinate(latitude: 40.7580, longitude: -73.9855))
        )
        let itinerary = try #require(await client.plan(request).itineraries.first)
        #expect(itinerary.legs.map(\.mode) == [.walk, .bus, .walk, .subway, .walk])

        let bus = itinerary.legs[1]
        #expect(bus.lineName == "B57")
        #expect(bus.from.stopId == "us-ny-MTA-BusBrooklyn_306087")
        #expect(bus.isRealtime)
        // Predicted 21:01, scheduled 21:03.
        #expect(bus.departureDelayMinutes == -2)

        // Live subway data, which Transitous doesn't have for NYC.
        let subway = itinerary.legs[3]
        #expect(subway.lineName == "A")
        #expect(subway.from.stopId == "us-ny-MTA-NYCSubway_A41N")
        #expect(subway.isRealtime)
        #expect(subway.departureDelayMinutes == -1)
    }

    @Test func sameStopsAsTransitous() throws {
        let transitous = try Self.stopIds(in: "plan-red-hook-to-times-square")
        let express = try Self.stopIds(in: "plan-red-hook-to-times-square-express")
        #expect(!express.isEmpty)
        #expect(express == transitous)
    }

    @Test func everyFixtureUsesBackendDatasets() throws {
        let directory = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            // Our own endpoints' answers (`vehicles-…` from `/api/vehicles/bus`) carry no MOTIS stops.
            .filter { !$0.lastPathComponent.hasPrefix("vehicles-") }
        #expect(urls.count >= 5)
        for url in urls {
            let name = url.deletingPathExtension().lastPathComponent
            let datasets = try Set(Self.stopIds(in: name).map { id in String(id.prefix { $0 != "_" }) })
            #expect(!datasets.isEmpty, "\(name) has no stop ids")
            #expect(datasets.isSubset(of: Self.backendDatasets), "\(name): \(datasets)")
        }
    }

    /// Every `stopId` in a fixture, in document order.
    static func stopIds(in fixture: String) throws -> [String] {
        var ids: [String] = []
        func walk(_ value: Any) {
            if let object = value as? [String: Any] {
                if let id = object["stopId"] as? String {
                    ids.append(id)
                }
                for key in object.keys.sorted() {
                    walk(object[key] as Any)
                }
            } else if let array = value as? [Any] {
                array.forEach(walk)
            }
        }
        try walk(JSONSerialization.jsonObject(with: FixtureTransport.fixture(fixture)))
        return ids
    }
}
