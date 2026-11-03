import Foundation
import HTTPTypes
import OpenAPIRuntime
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// How old the server's realtime data is, for telling riders when times may not be real time.
///
/// The MTA's terms require saying so whenever the data is more than a minute old. MOTIS sends no data-age header;
/// our server publishes each GTFS-RT feed's timestamp at `/metrics`, which ``TransitClient/realtimeDataAge()`` reads.
///
/// ```swift
/// let age = try await client.realtimeDataAge()
/// if age.mayNotBeRealTime(at: .now) { showBanner("Times may not be real time") }
/// ```
public struct RealtimeDataAge: Sendable, Hashable {
    /// How old realtime data may be before screens must say it may not be real time: one minute, per the MTA's terms.
    public static let realTimeLimit: TimeInterval = 60

    /// The feed tag prefix of the MTA subway's GTFS-RT feeds on our server (`us-ny-MTA-NYCSubway`).
    public static let subwayFeedPrefix = "us-ny-MTA-NYCSubway"

    /// When the oldest of the feeds was produced; `nil` where it's unknown, such as a feed the server hasn't loaded.
    public var feedTimestamp: Date?

    public init(feedTimestamp: Date?) {
        self.feedTimestamp = feedTimestamp
    }

    /// The age of the oldest feed whose tag starts with `feedPrefix` (the subway's by default), from `/metrics` text.
    ///
    /// Unknown (`nil` ``feedTimestamp``) where no feed matches, or any matching feed reports no timestamp yet.
    public init(metrics: String, feedPrefix: String = Self.subwayFeedPrefix) {
        let timestamps = Self.feedTimestamps(inMetrics: metrics).filter { $0.key.hasPrefix(feedPrefix) }.values
        if timestamps.isEmpty || timestamps.contains(where: { $0 == nil }) {
            feedTimestamp = nil
        } else {
            feedTimestamp = timestamps.compactMap(\.self).min()
        }
    }

    /// How many seconds old the data is at `now`, never negative; `nil` where unknown.
    public func age(at now: Date) -> TimeInterval? {
        feedTimestamp.map { max(now.timeIntervalSince($0), 0) }
    }

    /// Whether screens must say times may not be real time: the data is more than a minute old, or its age is unknown.
    public func mayNotBeRealTime(at now: Date) -> Bool {
        guard let age = age(at: now) else { return true }
        return age > Self.realTimeLimit
    }

    /// Each feed's timestamp by tag, from `nigiri_gtfsrt_feed_timestamp_seconds{tag="…"}` lines in Prometheus text;
    /// `nil` for a feed that reports `0` (not fetched yet).
    static func feedTimestamps(inMetrics metrics: String) -> [String: Date?] {
        let prefix = "nigiri_gtfsrt_feed_timestamp_seconds{"
        var timestamps: [String: Date?] = [:]
        for line in metrics.split(whereSeparator: \.isNewline) where line.hasPrefix(prefix) {
            guard let labelsEnd = line.firstIndex(of: "}") else { continue }
            let labels = line[line.index(line.startIndex, offsetBy: prefix.count) ..< labelsEnd]
            guard let tag = label("tag", in: labels),
                  let value = line[line.index(after: labelsEnd)...].split(separator: " ").first.flatMap({ Double($0) })
            else { continue }
            timestamps[tag] = value > 0 ? Date(timeIntervalSince1970: value) : nil
        }
        return timestamps
    }

    /// The value of `name="…"` among Prometheus labels such as `tag="us-ny-MTA-NYCSubway",le="1"`.
    private static func label(_ name: String, in labels: Substring) -> String? {
        for pair in labels.split(separator: ",") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == name else { continue }
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else { return nil }
            return String(value.dropFirst().dropLast())
        }
        return nil
    }
}

public extension TransitClient {
    /// How old the subway's realtime data is, from the server's `/metrics` (`GET /metrics`).
    ///
    /// A server that doesn't publish our feeds' timestamps (such as Transitous) answers with an unknown age, which
    /// ``RealtimeDataAge/mayNotBeRealTime(at:)`` treats as not real time.
    func realtimeDataAge() async throws(TransitError) -> RealtimeDataAge {
        let request = HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/metrics")
        do {
            let (response, body) = try await userAgent.intercept(
                request,
                body: nil,
                baseURL: baseURL,
                operationID: "metrics",
                next: { [transport] request, body, baseURL in
                    try await transport.send(request, body: body, baseURL: baseURL, operationID: "metrics")
                }
            )
            guard response.status == .ok else {
                throw TransitError(
                    undocumentedStatus: response.status.code,
                    payload: UndocumentedPayload(headerFields: response.headerFields, body: body)
                )
            }
            guard let body else { return RealtimeDataAge(feedTimestamp: nil) }
            return try await RealtimeDataAge(metrics: String(collecting: body, upTo: 4 * 1024 * 1024))
        } catch {
            throw TransitError(error)
        }
    }
}
