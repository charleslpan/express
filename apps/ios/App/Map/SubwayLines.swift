import Foundation
import TransitKit

/// The subway's track, as the map draws it when nothing else is selected: every line's route in the colour the MTA's
/// timetable gives it, with no buses.
///
/// It's bundled data (`SubwayLines/subway-lines.json`, made by `scripts/subway-lines/generate.py` from the MTA's GTFS
/// feed, which is also what the server's timetables are built from), so it draws at once and offline. Track that
/// several colours share is one ``Line`` with several colours.
struct SubwayLines: Equatable, Sendable {
    /// One piece of track and the colours of the routes that run over it.
    struct Line: Equatable, Sendable {
        /// The routes' colours as `RRGGBB` hex, ordered so a stripe stays the same from launch to launch.
        var colors: [String]
        var coordinates: [Coordinate]
    }

    var lines: [Line]

    /// The bundled lines, read once; empty if the file is missing or invalid.
    static let bundled: SubwayLines = {
        guard let url = Bundle.main.url(forResource: "subway-lines", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let lines = try? SubwayLines(data: data)
        else {
            assertionFailure("Missing or invalid subway-lines.json")
            return SubwayLines(lines: [])
        }
        return lines
    }()

    init(lines: [Line]) {
        self.lines = lines
    }

    /// Reads the JSON the generator writes: a `precision` and `lines` of `colors` and an encoded `path`.
    init(data: Data) throws {
        let document = try JSONDecoder().decode(Document.self, from: data)
        lines = document.lines.map { entry in
            Line(
                colors: entry.colors,
                coordinates: EncodedPolyline(points: entry.path, precision: document.precision, length: 0).coordinates
            )
        }
    }

    private struct Document: Decodable {
        var precision: Int
        var lines: [Entry]

        struct Entry: Decodable {
            var colors: [String]
            var path: String
        }
    }
}
