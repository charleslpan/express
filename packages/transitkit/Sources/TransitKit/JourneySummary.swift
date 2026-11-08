import Foundation

/// One stretch of the journey: a walk, or a ride on one line.
public struct JourneySegment: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable {
        /// Walking, merged across consecutive walking legs.
        case walk
        /// A ride on a line, with its bullet and mode.
        case ride(LineBullet, TransitMode)
    }

    public var id: String
    public var kind: Kind
    /// How long the stretch takes, in whole minutes rounded to the nearest (at least 1).
    public var minutes: Int

    public init(id: String, kind: Kind, minutes: Int) {
        self.id = id
        self.kind = kind
        self.minutes = minutes
    }
}

/// An itinerary at a glance, as a journey options list shows it: when it leaves and arrives, how long it takes, how
/// much of it is walking, how many changes it makes, and its legs as segments for a segment bar.
public struct JourneySummary: Sendable, Hashable, Identifiable {
    /// The itinerary's id, which picks it out among the options.
    public var id: String
    /// When the journey sets off from its start.
    public var departure: Date
    /// When it reaches its end.
    public var arrival: Date
    /// Door to door, in seconds.
    public var durationSeconds: Int
    /// Time on foot, in seconds: every walking leg, including those between platforms.
    public var walkingSeconds: Int
    /// How many times the rider changes vehicle: one fewer than the rides, never negative.
    public var transfers: Int
    /// When the first ride leaves its stop; `nil` for a journey on foot.
    public var firstRideDeparture: Date?
    /// Minutes late (positive) or early (negative) the first ride leaves, from realtime data; `nil` without it.
    public var firstRideDelayMinutes: Int?
    /// Whether realtime data stands behind any ride.
    public var isRealtime: Bool
    /// The trips the journey rides, in order, which stay the same when a refresh moves its times.
    public var tripIDs: [String]
    public var segments: [JourneySegment]

    public init(
        id: String,
        departure: Date,
        arrival: Date,
        durationSeconds: Int,
        walkingSeconds: Int,
        transfers: Int,
        firstRideDeparture: Date? = nil,
        firstRideDelayMinutes: Int? = nil,
        isRealtime: Bool = false,
        tripIDs: [String] = [],
        segments: [JourneySegment] = []
    ) {
        self.id = id
        self.departure = departure
        self.arrival = arrival
        self.durationSeconds = durationSeconds
        self.walkingSeconds = walkingSeconds
        self.transfers = transfers
        self.firstRideDeparture = firstRideDeparture
        self.firstRideDelayMinutes = firstRideDelayMinutes
        self.isRealtime = isRealtime
        self.tripIDs = tripIDs
        self.segments = segments
    }

    /// Summarises an itinerary from MOTIS.
    public init(_ itinerary: Itinerary) {
        let rides = itinerary.legs.filter { $0.tripId != nil }
        var segments: [JourneySegment] = []
        var walkSeconds = 0
        var walkStart: Int?
        for (index, leg) in itinerary.legs.enumerated() {
            if leg.tripId != nil, let bullet = leg.lineBullet {
                if let start = walkStart {
                    segments.append(Self.walk(seconds: walkSeconds, index: start))
                    walkStart = nil
                    walkSeconds = 0
                }
                segments.append(JourneySegment(
                    id: "\(index)-\(leg.tripId ?? "")",
                    kind: .ride(bullet, leg.mode),
                    minutes: Self.minutes(leg.duration)
                ))
            } else if leg.mode == .walk {
                walkStart = walkStart ?? index
                walkSeconds += leg.duration
            }
        }
        if let start = walkStart {
            segments.append(Self.walk(seconds: walkSeconds, index: start))
        }

        self.init(
            id: itinerary.id,
            departure: itinerary.startTime,
            arrival: itinerary.endTime,
            durationSeconds: itinerary.duration,
            walkingSeconds: itinerary.legs.filter { $0.mode == .walk }.map(\.duration).reduce(0, +),
            transfers: max(rides.count - 1, 0),
            firstRideDeparture: rides.first?.startTime,
            firstRideDelayMinutes: rides.first?.departureDelayMinutes,
            isRealtime: rides.contains(where: \.realTime),
            tripIDs: rides.compactMap(\.tripId),
            segments: segments
        )
    }

    /// The duration for display, such as "22 min".
    public var formattedDuration: String {
        DurationFormat.string(seconds: durationSeconds)
    }

    /// The walking time for display, such as "7 min".
    public var formattedWalking: String {
        DurationFormat.string(seconds: walkingSeconds)
    }

    /// Whether the journey is on foot all the way.
    public var isWalkOnly: Bool {
        tripIDs.isEmpty
    }

    /// Whole minutes from `now` until the first ride leaves (or, on foot, the walk starts): rounded down, never
    /// negative.
    public func minutesUntilDeparture(from now: Date) -> Int {
        max(Int(((firstRideDeparture ?? departure).timeIntervalSince(now) / 60).rounded(.down)), 0)
    }

    private static func walk(seconds: Int, index: Int) -> JourneySegment {
        JourneySegment(id: "\(index)-walk", kind: .walk, minutes: minutes(seconds))
    }

    private static func minutes(_ seconds: Int) -> Int {
        max(Int((Double(seconds) / 60).rounded()), 1)
    }
}

/// One journey option: the itinerary MOTIS planned, and its summary.
public struct JourneyOption: Sendable, Hashable, Identifiable {
    public var itinerary: Itinerary
    public var summary: JourneySummary

    public var id: String {
        summary.id
    }

    public init(_ itinerary: Itinerary) {
        self.itinerary = itinerary
        summary = JourneySummary(itinerary)
    }
}

/// Turns a plan into the options a rider chooses between, in the order they'd choose.
public enum JourneyOptions {
    /// The plan's itineraries and direct walks as options: departed ones dropped (for ``PlanRequest/Time/now``),
    /// duplicates dropped, sorted with ``sorted(_:for:)``.
    public static func options(from response: PlanResponse, for time: PlanRequest.Time, now: Date) -> [JourneyOption] {
        var seen = Set<String>()
        let options = (response.itineraries + response.direct.filter { $0.legs.allSatisfy { $0.mode == .walk } })
            .map(JourneyOption.init)
            .filter { seen.insert($0.id).inserted }
            .filter { option in
                // A minute's grace, so the option the rider is running for doesn't vanish under them.
                guard case .now = time else { return true }
                return (option.summary.firstRideDeparture ?? option.summary.departure) >= now.addingTimeInterval(-60)
            }
        let order = sorted(options.map(\.summary), for: time).map(\.id)
        return order.compactMap { id in options.first { $0.id == id } }
    }

    /// Summaries in the order a rider weighs them.
    ///
    /// Leaving now or at a time: the earliest arrival first. Arriving by a time: the latest departure first, since
    /// every option arrives in time and the latest leaves the rider the most of their day. Ties go to fewer
    /// transfers, then less walking, then the shorter journey.
    public static func sorted(_ summaries: [JourneySummary], for time: PlanRequest.Time) -> [JourneySummary] {
        summaries.sorted { lhs, rhs in
            switch time {
            case .now, .departAt:
                if lhs.arrival != rhs.arrival {
                    return lhs.arrival < rhs.arrival
                }
            case .arriveBy:
                if lhs.departure != rhs.departure {
                    return lhs.departure > rhs.departure
                }
            }
            if lhs.transfers != rhs.transfers {
                return lhs.transfers < rhs.transfers
            }
            if lhs.walkingSeconds != rhs.walkingSeconds {
                return lhs.walkingSeconds < rhs.walkingSeconds
            }
            if lhs.durationSeconds != rhs.durationSeconds {
                return lhs.durationSeconds < rhs.durationSeconds
            }
            return lhs.id < rhs.id
        }
    }
}
