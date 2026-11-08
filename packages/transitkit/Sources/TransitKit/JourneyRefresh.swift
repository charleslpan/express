import Foundation

// Keeping a planned journey live: each ride's times, stops, and cancellation from its trip (`GET /api/v6/trip`),
// which stays the same trip however the rider's location or the clock moves, unlike planning again.

public extension Itinerary {
    /// The itinerary with each ride brought up to date from its trip, by trip id: its boarding and alighting times,
    /// the stops between, and whether it's cancelled. Walks after a ride move with its arrival; walks before the
    /// first ride stay put, as the rider sets off when they planned. A ride whose trip is missing, or no longer calls
    /// at its stops, keeps what it had.
    func refreshed(withTrips trips: [String: Itinerary]) -> Itinerary {
        var itinerary = self
        var shift: TimeInterval = 0
        for index in itinerary.legs.indices {
            var leg = itinerary.legs[index]
            if let tripId = leg.tripId {
                if let trip = trips[tripId], let refreshed = leg.refreshed(from: trip) {
                    leg = refreshed
                }
                shift = leg.endTime.timeIntervalSince(legs[index].endTime)
            } else if shift != 0 {
                leg.startTime += shift
                leg.endTime += shift
            }
            itinerary.legs[index] = leg
        }
        if let first = itinerary.legs.first, let last = itinerary.legs.last {
            itinerary.startTime = first.startTime
            itinerary.endTime = last.endTime
            itinerary.duration = Int(last.endTime.timeIntervalSince(first.startTime))
        }
        return itinerary
    }
}

extension Leg {
    /// This ride as it stands in `trip` (MOTIS's trip as an itinerary of one leg): `nil` where the trip doesn't call
    /// at the ride's stops in order.
    func refreshed(from trip: Itinerary) -> Leg? {
        guard let tripLeg = trip.legs.first(where: { $0.tripId == tripId }) ?? trip.tripLeg else { return nil }
        let stops = [tripLeg.from] + (tripLeg.intermediateStops ?? []) + [tripLeg.to]
        guard let board = stops.firstIndex(where: { $0.matches(from) }),
              let alight = stops[(board + 1)...].firstIndex(where: { $0.matches(to) })
        else { return nil }

        var leg = self
        leg.from = stops[board]
        leg.to = stops[alight]
        leg.intermediateStops = Array(stops[(board + 1) ..< alight])
        leg.startTime = stops[board].departure ?? startTime
        leg.scheduledStartTime = stops[board].scheduledDeparture ?? scheduledStartTime
        leg.endTime = stops[alight].arrival ?? endTime
        leg.scheduledEndTime = stops[alight].scheduledArrival ?? scheduledEndTime
        leg.duration = Int(leg.endTime.timeIntervalSince(leg.startTime))
        leg.realTime = tripLeg.realTime
        leg.cancelled = tripLeg.cancelled
        // The trip's track is the whole line's; the ride keeps its own stretch of it.
        return leg
    }
}

private extension Place {
    /// Whether this is the same stop as `other`: by stop id where both have one, else by name.
    func matches(_ other: Place) -> Bool {
        if let stopId, let otherId = other.stopId {
            return stopId == otherId
        }
        return name == other.name
    }
}

public extension TransitClient {
    /// The itinerary with every ride brought up to date from its trip (``Itinerary/refreshed(withTrips:)``), its
    /// trips fetched at once.
    ///
    /// A trip that can't be fetched keeps its ride as it was; it throws only where every trip fails, with the first
    /// failure. A journey on foot comes back as it is.
    func refreshRides(of itinerary: Itinerary) async throws(TransitError) -> Itinerary {
        let tripIds = Array(Set(itinerary.transitLegs.compactMap(\.tripId)))
        guard !tripIds.isEmpty else { return itinerary }
        let results = await withTaskGroup(of: (String, Result<Itinerary, TransitError>).self) { group in
            for id in tripIds {
                group.addTask {
                    do throws(TransitError) {
                        return try await (id, .success(trip(id: id)))
                    } catch {
                        return (id, .failure(error))
                    }
                }
            }
            var results: [String: Result<Itinerary, TransitError>] = [:]
            for await (id, result) in group {
                results[id] = result
            }
            return results
        }
        let trips = results.compactMapValues { try? $0.get() }
        if trips.isEmpty, let failure = tripIds.lazy.compactMap({ id -> TransitError? in
            if case let .failure(error) = results[id] {
                error
            } else {
                nil
            }
        }).first {
            throw failure
        }
        return itinerary.refreshed(withTrips: trips)
    }
}
