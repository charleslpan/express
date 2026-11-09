import Foundation

// The logic behind a journey's step-by-step plan: its walks, rides, and the transfers between them, how long each
// transfer leaves to change (and whether that's tight or already missed on live times), and whether a cancelled ride
// makes the journey impossible.

/// One stop a ride boards at, passes, or alights at, with its time there (realtime where the feed predicts it).
public struct JourneyStopTime: Sendable, Hashable, Identifiable {
    /// The stop's place in its ride and its id, so a ride that passes a stop twice lists it twice.
    public var id: String
    public var name: String
    public var stopId: String?
    public var coordinate: Coordinate
    /// When the vehicle is at the stop: its departure where it leaves from here, else its arrival.
    public var time: Date
    /// When the timetable says it's there.
    public var scheduledTime: Date
    /// Whether realtime data stands behind the time.
    public var isRealtime: Bool
    /// Whether realtime data skips the stop, or the rider may not board or alight there any more.
    public var isCancelled: Bool
    /// The platform or track, as the feed gives it (live where it has changed); `nil` where it gives none, as the
    /// MTA's subway and buses don't.
    public var track: String?

    /// The stop as a ride's place: `departs` reads its departure (boarding, passing), else its arrival (alighting).
    init(place: Place, index: Int, departs: Bool, fallback: Date) {
        id = "\(index)|\(place.id)"
        name = place.name
        stopId = place.stopId
        coordinate = place.coordinate
        let time = departs ? place.departure ?? place.arrival : place.arrival ?? place.departure
        let scheduled = departs
            ? place.scheduledDeparture ?? place.scheduledArrival
            : place.scheduledArrival ?? place.scheduledDeparture
        self.time = time ?? fallback
        scheduledTime = scheduled ?? time ?? fallback
        isRealtime = place.isRealtime
        let refused = departs ? place.pickupType == .notAllowed : place.dropoffType == .notAllowed
        isCancelled = place.cancelled == true || refused
        track = [place.track, place.scheduledTrack].lazy.compactMap(\.self).first { !$0.isEmpty }
    }

    /// Whole minutes late (positive) or early (negative); `nil` without realtime data.
    public var delayMinutes: Int? {
        isRealtime ? Leg.minutes(from: scheduledTime, to: time) : nil
    }

    /// How the time stands against the timetable; ``DepartureStatus/uncertain`` for a live time when the realtime
    /// data is stale.
    public func status(realtimeIsStale: Bool = false) -> DepartureStatus {
        DepartureStatus(
            delayMinutes: delayMinutes,
            isRealtime: isRealtime,
            isCancelled: isCancelled,
            realtimeIsStale: realtimeIsStale
        )
    }
}

/// A walk at the start or end of a journey (walks between rides are part of their ``JourneyTransfer``).
public struct JourneyWalk: Sendable, Hashable, Identifiable {
    public var id: String
    /// The leg's place in the itinerary, for drawing it on the map.
    public var legIndex: Int
    /// Where the walk starts and ends, such as "14 St-Union Sq"; MOTIS names the journey's own ends `START`/`END`.
    public var from: String
    public var to: String
    public var start: Date
    public var end: Date
    public var seconds: Int
    /// How far it goes, in metres; `nil` where MOTIS doesn't say.
    public var distanceMeters: Double?
    /// Turn-by-turn, where MOTIS returns steps; empty otherwise.
    public var instructions: [WalkInstruction]

    init(leg: Leg, index: Int) {
        id = "\(index)-walk"
        legIndex = index
        from = leg.from.name
        to = leg.to.name
        start = leg.startTime
        end = leg.endTime
        seconds = leg.duration
        distanceMeters = leg.distance
        instructions = WalkInstruction.instructions(from: leg.steps ?? [])
    }

    /// The time for display, such as "4 min".
    public var formattedDuration: String {
        DurationFormat.string(seconds: seconds)
    }

    /// The distance for display, such as "0.2 mi"; `nil` where unknown.
    public var formattedDistance: String? {
        distanceMeters.map(DistanceFormat.string(meters:))
    }
}

/// A ride on one line: where it boards and alights, the stops between, and whether the trip still runs.
public struct JourneyRide: Sendable, Hashable, Identifiable {
    public var id: String
    /// The leg's place in the itinerary, for drawing it on the map.
    public var legIndex: Int
    public var tripId: String
    public var bullet: LineBullet?
    public var mode: TransitMode
    /// Where the vehicle is headed, such as "Pelham Bay Park".
    public var headsign: String?
    /// Which way it runs, as the MTA signs it, such as "Uptown & The Bronx"; `nil` where Express doesn't know.
    public var direction: String?
    public var board: JourneyStopTime
    public var alight: JourneyStopTime
    /// The stops it calls at between the two, in order.
    public var intermediateStops: [JourneyStopTime]
    /// Whether realtime data cancels the trip, or the stop it boards or alights at.
    public var isCancelled: Bool
    /// Whether the rider stays aboard from the ride before, as the line changes its name.
    public var staysAboard: Bool

    init(leg: Leg, index: Int, tripId: String) {
        id = "\(index)-\(tripId)"
        legIndex = index
        self.tripId = tripId
        bullet = leg.lineBullet
        mode = leg.mode
        headsign = leg.headsign.flatMap { $0.isEmpty ? nil : $0 }
        board = JourneyStopTime(place: leg.from, index: 0, departs: true, fallback: leg.startTime)
        // The leg's own times win over its places', as MOTIS fills both and the leg's are always there.
        board.time = leg.startTime
        board.scheduledTime = leg.scheduledStartTime
        let stops = leg.intermediateStops ?? []
        intermediateStops = stops.enumerated().map { offset, place in
            JourneyStopTime(place: place, index: offset + 1, departs: true, fallback: leg.startTime)
        }
        alight = JourneyStopTime(place: leg.to, index: stops.count + 1, departs: false, fallback: leg.endTime)
        alight.time = leg.endTime
        alight.scheduledTime = leg.scheduledEndTime
        isCancelled = leg.cancelled == true || board.isCancelled || alight.isCancelled
        staysAboard = leg.interlineWithPreviousLeg == true
        direction = SubwayDirection.label(line: leg.routeShortName ?? bullet?.text, stopId: leg.from.stopId)
    }

    /// How many stops the ride travels: the stops between, and the one it alights at.
    public var stopCount: Int {
        intermediateStops.count + 1
    }

    /// "1 stop", "7 stops".
    public var formattedStopCount: String {
        stopCount == 1 ? "1 stop" : "\(stopCount) stops"
    }

    /// The ride's time aboard for display, such as "8 min".
    public var formattedDuration: String {
        DurationFormat.string(seconds: Int(alight.time.timeIntervalSince(board.time)))
    }
}

/// A change between two rides: the walk (if any) from one to the other, and the time left over to wait.
public struct JourneyTransfer: Sendable, Hashable, Identifiable {
    /// How a transfer stands on the latest times.
    public enum Status: Sendable, Hashable {
        /// Time enough to change.
        case comfortable
        /// Less than ``JourneyTransfer/tightThreshold`` to spare: a delay or a slow walk could miss it.
        case tight
        /// The next ride leaves before the rider can get to it.
        case missed
    }

    /// Less time than this to spare after the walk makes a transfer tight: two minutes.
    public static let tightThreshold: TimeInterval = 120

    public var id: String
    /// The legs walked between the rides (none for a cross-platform change), for drawing them on the map.
    public var legIndices: [Int]
    /// Where the rider gets off, and where they board next (often the same station).
    public var from: String
    public var to: String
    /// When the first ride arrives, and when the next leaves.
    public var arrival: Date
    public var departure: Date
    /// Time on foot between the two, in seconds.
    public var walkSeconds: Int
    /// How far the walk goes, in metres; `nil` where MOTIS doesn't say or there's no walk.
    public var walkDistanceMeters: Double?

    init(from ride: JourneyRide, to next: JourneyRide, walks: [Leg], legIndices: [Int]) {
        id = "\(ride.legIndex)-\(next.legIndex)-transfer"
        self.legIndices = legIndices
        from = ride.alight.name
        to = next.board.name
        arrival = ride.alight.time
        departure = next.board.time
        walkSeconds = walks.map(\.duration).reduce(0, +)
        let distances = walks.compactMap(\.distance)
        walkDistanceMeters = distances.isEmpty ? nil : distances.reduce(0, +)
    }

    /// Seconds left to wait once the walk is done; negative where the next ride leaves before the rider gets there.
    public var waitSeconds: Int {
        Int(departure.timeIntervalSince(arrival)) - walkSeconds
    }

    public var status: Status {
        let wait = TimeInterval(waitSeconds)
        if wait < 0 {
            return .missed
        }
        return wait < Self.tightThreshold ? .tight : .comfortable
    }

    /// Whether the rider changes station, rather than platform within one.
    public var changesStation: Bool {
        from != to
    }

    /// The wait for display: "3 min wait", "No wait", or, for a missed transfer, "Missed by 2 min". English until the
    /// app localizes.
    public var formattedWait: String {
        let wait = waitSeconds
        if wait < 0 {
            return "Missed by \(DurationFormat.string(seconds: -wait))"
        }
        return wait < 30 ? "No wait" : "\(DurationFormat.string(seconds: wait)) wait"
    }

    /// The walk for display, such as "2 min walk"; `nil` for a change on the same platform.
    public var formattedWalk: String? {
        walkSeconds > 0 ? "\(DurationFormat.string(seconds: walkSeconds)) walk" : nil
    }
}

/// One step of a journey's plan, in order.
public enum JourneyStep: Sendable, Hashable, Identifiable {
    case walk(JourneyWalk)
    case ride(JourneyRide)
    case transfer(JourneyTransfer)

    public var id: String {
        switch self {
        case let .walk(walk): walk.id
        case let .ride(ride): ride.id
        case let .transfer(transfer): transfer.id
        }
    }

    /// The itinerary's legs the step covers, for drawing it on the map: none for a change on one platform.
    public var legIndices: [Int] {
        switch self {
        case let .walk(walk): [walk.legIndex]
        case let .ride(ride): [ride.legIndex]
        case let .transfer(transfer): transfer.legIndices
        }
    }
}

/// What stops a journey working on the latest times, worst first.
public enum JourneyProblem: Sendable, Hashable {
    /// A ride's trip is cancelled, or skips the stop it boards or alights at.
    case cancelled(JourneyRide)
    /// A transfer can't be made: the next ride leaves before the rider gets to it.
    case missedTransfer(JourneyTransfer)

    /// The problem in a sentence, such as "The 6 to Pelham Bay Park is cancelled." English until the app localizes.
    public var message: String {
        switch self {
        case let .cancelled(ride):
            let line = ride.lineName
            if ride.board.isCancelled {
                return "The \(line) no longer stops at \(ride.board.name)."
            }
            if ride.alight.isCancelled {
                return "The \(line) no longer stops at \(ride.alight.name)."
            }
            let headsign = ride.headsign.map { " to \($0)" } ?? ""
            return "The \(line)\(headsign) is cancelled."
        case let .missedTransfer(transfer):
            let wait = DurationFormat.string(seconds: -transfer.waitSeconds)
            return "The connection at \(transfer.to) is missed by \(wait) on live times."
        }
    }
}

extension JourneyRide {
    /// The line as riders say it: "6", "M101"; "train" or "bus" where the feed names none.
    var lineName: String {
        bullet?.text ?? (mode == .bus ? "bus" : "train")
    }
}

/// An itinerary as a step-by-step plan: its summary, then walks, rides, and the transfers between rides, and what
/// (if anything) stops it working on the latest times.
public struct JourneyPlan: Sendable, Hashable {
    public var summary: JourneySummary
    public var steps: [JourneyStep]

    public init(_ itinerary: Itinerary) {
        summary = JourneySummary(itinerary)
        var steps: [JourneyStep] = []
        // Walks after a ride wait here until the next ride shows whether they're a transfer or the final walk.
        var pending: [(index: Int, leg: Leg)] = []
        var lastRide: JourneyRide?
        for (index, leg) in itinerary.legs.enumerated() {
            if let tripId = leg.tripId {
                let ride = JourneyRide(leg: leg, index: index, tripId: tripId)
                if let lastRide, !ride.staysAboard {
                    steps.append(.transfer(JourneyTransfer(
                        from: lastRide,
                        to: ride,
                        walks: pending.map(\.leg),
                        legIndices: pending.map(\.index)
                    )))
                } else {
                    steps += pending.map { .walk(JourneyWalk(leg: $0.leg, index: $0.index)) }
                }
                pending = []
                steps.append(.ride(ride))
                lastRide = ride
            } else if lastRide == nil {
                steps.append(.walk(JourneyWalk(leg: leg, index: index)))
            } else {
                pending.append((index, leg))
            }
        }
        steps += pending.map { .walk(JourneyWalk(leg: $0.leg, index: $0.index)) }
        self.steps = steps
    }

    public var rides: [JourneyRide] {
        steps.compactMap { step in
            if case let .ride(ride) = step {
                ride
            } else {
                nil
            }
        }
    }

    public var transfers: [JourneyTransfer] {
        steps.compactMap { step in
            if case let .transfer(transfer) = step {
                transfer
            } else {
                nil
            }
        }
    }

    /// What stops the journey working, if anything: the first cancelled ride, else the first missed transfer.
    public var problem: JourneyProblem? {
        if let ride = rides.first(where: \.isCancelled) {
            return .cancelled(ride)
        }
        return transfers.first { $0.status == .missed }.map(JourneyProblem.missedTransfer)
    }
}
