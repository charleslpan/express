#if DEBUG
    import SwiftUI

    /// Real New York lines in the MTA's colours, for the gallery and previews. The app gets these values from the
    /// feed; nothing outside debug builds reads them.
    extension TransitLine {
        private static func subway(_ name: String, _ hex: String, express: Bool = false) -> TransitLine {
            // The subway feed gives a text colour for every line: black on the N, Q, R, and W's yellow, white
            // elsewhere.
            let color = LineColor(hex: hex) ?? .black
            return TransitLine(
                name: name,
                mode: .subway,
                color: color,
                textColor: hex == "FCCC0A" ? .black : .white,
                isExpress: express
            )
        }

        private static func bus(_ name: String, _ hex: String) -> TransitLine {
            // No text colour, so GlassUI picks black or white for contrast.
            TransitLine(name: name, mode: .bus, color: LineColor(hex: hex) ?? .black)
        }

        static let line1 = subway("1", "EE352E")
        static let line4 = subway("4", "00933C")
        static let line6X = subway("6", "00933C", express: true)
        static let lineA = subway("A", "0039A6")
        static let lineF = subway("F", "FF6319")
        static let lineG = subway("G", "6CBE45")
        static let lineL = subway("L", "A7A9AC")
        static let lineN = subway("N", "FCCC0A")
        static let line7 = subway("7", "B933AD")
        static let line7X = subway("7", "B933AD", express: true)
        static let lineS = subway("S", "808183")
        static let lineSIR = TransitLine(name: "SIR", mode: .rail, color: LineColor(hex: "0078C6") ?? .black)
        static let busM15 = bus("M15", "00AEEF")
        static let busM15SBS = bus("M15 SBS", "2850AD")
        static let busB44SBS = bus("B44 SBS", "2850AD")
        static let busX27 = bus("X27", "00933C")

        /// The gallery's lines, in the order they're shown.
        static let samples: [TransitLine] = [
            line1, line4, line6X, lineA, lineF, lineG, lineL, lineN, line7, line7X, lineS, lineSIR, busM15, busB44SBS,
            busX27,
        ]
    }

    extension JourneyLeg {
        /// Journeys across town, from a single ride to five legs with short walks between.
        static let sampleJourneys: [[JourneyLeg]] = [
            [.walk(minutes: 4), .ride(TransitLine.line6X, minutes: 12), .walk(minutes: 3)],
            [
                .walk(minutes: 2),
                .ride(TransitLine.lineA, minutes: 18),
                .ride(TransitLine.lineL, minutes: 9),
                .walk(minutes: 6),
            ],
            [.walk(minutes: 5), .ride(TransitLine.busM15SBS, minutes: 22), .walk(minutes: 1)],
            [
                .walk(minutes: 3), .ride(TransitLine.lineN, minutes: 6), .walk(minutes: 2),
                .ride(TransitLine.line7, minutes: 14), .ride(TransitLine.busX27, minutes: 25), .walk(minutes: 4),
            ],
            [.ride(TransitLine.lineSIR, minutes: 23), .walk(minutes: 8)],
        ]
    }

    @MainActor
    extension DepartureRow {
        /// Departures from around Manhattan, in every realtime state.
        static var samples: [DepartureRow] {
            [
                DepartureRow(
                    line: TransitLine.busM15SBS,
                    headsign: "South Ferry",
                    detail: "1 Av / E 14 St",
                    departures: [
                        DepartureTime(minutes: 3, status: .live),
                        DepartureTime(minutes: 11, status: .scheduled),
                        DepartureTime(minutes: 19, status: .scheduled),
                    ]
                ),
                DepartureRow(
                    line: TransitLine.line6X,
                    headsign: "Pelham Bay Park",
                    detail: "Uptown",
                    departures: [
                        DepartureTime(minutes: 0, status: .live),
                        DepartureTime(minutes: 6, status: .delayed(minutes: 3)),
                        DepartureTime(minutes: 14, status: .live),
                    ]
                ),
                DepartureRow(
                    line: TransitLine.lineN,
                    headsign: "Astoria–Ditmars Blvd",
                    detail: "Uptown & Queens",
                    departures: [
                        DepartureTime(minutes: 4, status: .cancelled),
                        DepartureTime(minutes: 9, status: .live),
                    ]
                ),
                DepartureRow(
                    line: TransitLine.lineL,
                    headsign: "Canarsie–Rockaway Pkwy",
                    departures: [
                        DepartureTime(minutes: 7, status: .uncertain),
                        DepartureTime(minutes: 15, status: .uncertain),
                    ]
                ),
                DepartureRow(
                    line: TransitLine.lineSIR,
                    headsign: "Tottenville",
                    detail: "St George",
                    departures: [DepartureTime(minutes: 12, status: .scheduled)]
                ),
                DepartureRow(line: TransitLine.busX27, headsign: "Bay Ridge", departures: []),
            ]
        }
    }
#endif
