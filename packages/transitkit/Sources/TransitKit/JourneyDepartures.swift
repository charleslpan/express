import Foundation

// More departures of a route than the planner offered: for a journey that is a single ride, the next trips of its line
// from the stop it boards at, each checked against its own trip before it counts. A journey with changes never gets
// this: a later first ride says nothing about whether its connection works.

public extension Itinerary {
    /// This journey made on another trip of its one ride: the ride replaced, and the walks before and after it moved
    /// to keep the same gaps. `nil` unless the journey has exactly one ride.
    func riding(_ ride: Leg) -> Itinerary? {
        let rides = legs.indices.filter { legs[$0].tripId != nil }
        guard rides.count == 1, let index = rides.first else { return nil }
        let planned = legs[index]
        let before = ride.startTime.timeIntervalSince(planned.startTime)
        let after = ride.endTime.timeIntervalSince(planned.endTime)

        var itinerary = self
        for position in legs.indices where position != index {
            let shift = position < index ? before : after
            itinerary.legs[position].startTime += shift
            itinerary.legs[position].endTime += shift
            itinerary.legs[position].scheduledStartTime += shift
            itinerary.legs[position].scheduledEndTime += shift
        }
        itinerary.legs[index] = ride
        if let first = itinerary.legs.first, let last = itinerary.legs.last {
            itinerary.startTime = first.startTime
            itinerary.endTime = last.endTime
            itinerary.duration = Int(last.endTime.timeIntervalSince(first.startTime))
        }
        itinerary.id = "\(id)|\(ride.tripId ?? "")"
        return itinerary
    }
}

/// How many departures a stop is asked for beyond the ones wanted, since some will turn out not to go the way the
/// rider is going.
private let supplementSpare = 2

public extension TransitClient {
    /// The next trips of a single-ride journey's line, as the same journey on each: found from the departures at the
    /// stop it boards at, and kept only when the trip itself calls at the boarding stop and then the alighting stop.
    ///
    /// It looks at no more than `limit` plus two trips, so one open route costs a stop's departures and a handful of
    /// trips at most. It returns nothing for a journey with changes (a later first ride proves nothing about its
    /// connection) or one whose route or stops have no ids, and quietly nothing where the server can't answer: these
    /// are extras on top of what the planner found.
    ///
    /// - Parameters:
    ///   - itinerary: The journey to find more departures of.
    ///   - known: The trip ids already offered, which don't count again.
    ///   - after: The earliest a departure may leave: trips before it are ones the rider couldn't reach.
    ///   - limit: The most journeys to return.
    /// - Returns: The journeys on other trips, soonest first.
    func upcomingTrips(
        like itinerary: Itinerary,
        excluding known: Set<String>,
        after: Date,
        limit: Int
    ) async -> [Itinerary] {
        guard limit > 0, let pattern = JourneyRoutePattern(itinerary), pattern.isDirect,
              let planned = itinerary.legs.first(where: { $0.tripId != nil }),
              let boardStopId = planned.from.stopId
        else { return [] }

        let request = DeparturesRequest(
            stopId: boardStopId,
            time: after,
            count: limit + supplementSpare,
            window: StopBoard.window,
            transitModes: [planned.mode]
        )
        guard let response = try? await departures(request) else { return [] }
        let candidates = response.stopTimes.upcomingCandidates(
            like: planned,
            excluding: known,
            after: after,
            limit: limit + supplementSpare
        )

        let verified = await withTaskGroup(of: Itinerary?.self) { group in
            for candidate in candidates {
                group.addTask {
                    let tripId = candidate.tripId
                    guard let trip = try? await self.trip(id: tripId) else { return nil }
                    var template = planned
                    template.tripId = tripId
                    template.headsign = candidate.headsign
                    guard let ride = template.refreshed(from: trip), ride.cancelled != true else { return nil }
                    return itinerary.riding(ride)
                }
            }
            var verified: [Itinerary] = []
            for await journey in group {
                if let journey {
                    verified.append(journey)
                }
            }
            return verified
        }
        return Array(verified.sorted { $0.startTime < $1.startTime }.prefix(limit))
    }
}

extension [Departure] {
    /// The departures that could be another trip of the same ride as `ride`: its route, its direction where it has
    /// one, from the stop it boards at, not cancelled, not one of the `known` trips, leaving at or after `after`;
    /// soonest first, each trip once, at most `limit`.
    func upcomingCandidates(like ride: Leg, excluding known: Set<String>, after: Date, limit: Int) -> [Departure] {
        var seen = known
        return filter { departure in
            guard departure.routeId == ride.routeId,
                  ride.directionId.map({ $0.isEmpty || $0 == departure.directionId }) ?? true,
                  departure.place.stopId == ride.from.stopId,
                  !departure.isCancelled,
                  let time = departure.time, time >= after
            else { return false }
            return true
        }
        .sorted { ($0.time ?? .distantFuture) < ($1.time ?? .distantFuture) }
        .filter { seen.insert($0.tripId).inserted }
        .prefix(limit)
        .map(\.self)
    }
}
