import Foundation

// The logic behind a stop's full departures board: every line and direction that calls there, in a fixed order a
// rider can learn, with each one's upcoming departures.

/// A stop's upcoming departures, grouped by line and direction, as fetched at one moment.
///
/// ```swift
/// let response = try await client.departures(StopBoard.request(stopId: id))
/// let board = StopBoard(stopTimes: response.stopTimes, fetchedAt: now, dataAge: age)
/// ```
public struct StopBoard: Sendable, Hashable {
    /// Each line's departures in one direction, in board order (``Swift/Sequence/stopBoardLines(at:limit:)``).
    public var lines: [LineDepartures]
    /// When the departures were fetched.
    public var fetchedAt: Date
    /// How old the server's realtime data was when they were fetched.
    public var dataAge: RealtimeDataAge

    /// How many departures each line and direction keeps.
    public static let departuresPerLine = 4
    /// How far ahead the board looks: the rest of the evening's service at a quiet stop, not just the next few.
    public static let window: TimeInterval = 90 * 60
    /// The fewest departures the board asks for, however far off they are.
    public static let minimumCount = 40

    /// Builds the board from a stop's departures, keeping those still to leave at `fetchedAt`.
    public init(
        stopTimes: [Departure],
        fetchedAt: Date,
        dataAge: RealtimeDataAge,
        departuresPerLine: Int = Self.departuresPerLine
    ) {
        lines = stopTimes.stopBoardLines(at: fetchedAt, limit: departuresPerLine)
        self.fetchedAt = fetchedAt
        self.dataAge = dataAge
    }

    /// The request for a stop's board: its departures over the next ``window`` (at least ``minimumCount``).
    public static func request(stopId: String, modes: [TransitMode]? = nil) -> DeparturesRequest {
        DeparturesRequest(stopId: stopId, count: minimumCount, window: window, transitModes: modes)
    }

    /// Whether nothing is left to leave: no more departures today, as far as the board looks.
    public var isEmpty: Bool {
        lines.isEmpty
    }

    /// Each line that calls at the stop once (its first direction in board order), for the bullets beside the stop's
    /// name.
    public var distinctLines: [LineDepartures] {
        var lines: [LineDepartures] = []
        for line in self.lines where !lines.contains(where: { $0.bullet == line.bullet }) {
            lines.append(line)
        }
        return lines
    }

    /// Whether screens must say times may not be real time, as the MTA's terms require: the board was fetched more
    /// than ``RealtimeDataAge/realTimeLimit`` ago, or the server's realtime data was older than that, or of unknown
    /// age, when it was.
    public func mayNotBeRealTime(at now: Date) -> Bool {
        now.timeIntervalSince(fetchedAt) > RealtimeDataAge.realTimeLimit || dataAge.mayNotBeRealTime(at: now)
    }
}

public extension Sequence<Departure> {
    /// The departures still to leave at `now`, grouped by line and direction (each keeping its first `limit`), in
    /// the order a station's board lists them: subway before bus, then by line ("1", "2", "A", "B", "L", "M14A"),
    /// then by direction (`0` before `1`; uptown before downtown on the subway).
    ///
    /// Unlike ``Swift/Sequence/groupedByLineAndDirection(at:limit:)``, which puts the soonest-leaving line first for
    /// a glance, this order stays put as trains come and go, so a rider finds their line where it was.
    func stopBoardLines(at now: Date, limit: Int = StopBoard.departuresPerLine) -> [LineDepartures] {
        groupedByLineAndDirection(at: now, limit: limit).sorted { lhs, rhs in
            let left = StopBoard.modeRank(lhs.mode)
            let right = StopBoard.modeRank(rhs.mode)
            if left != right {
                return left < right
            }
            if lhs.bullet.text != rhs.bullet.text {
                return lhs.bullet.text.localizedStandardCompare(rhs.bullet.text) == .orderedAscending
            }
            // A local and its express variant (6 and <6>) share a name: the local first.
            if lhs.bullet.shape != rhs.bullet.shape {
                return lhs.bullet.shape != .diamond
            }
            return lhs.directionId < rhs.directionId
        }
    }
}

extension StopBoard {
    /// Where a mode sorts on the board: the subway first, then buses, then anything else.
    static func modeRank(_ mode: TransitMode) -> Int {
        switch mode {
        case .subway, .metro: 0
        case .bus, .coach: 1
        default: 2
        }
    }
}
