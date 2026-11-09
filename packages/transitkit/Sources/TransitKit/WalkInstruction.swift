import Foundation

/// One turn-by-turn instruction on a walk, such as "Turn left onto E 14th St".
public struct WalkInstruction: Sendable, Hashable, Identifiable {
    public var id: Int
    /// What to do, in a sentence without a full stop. English until the app localizes.
    public var text: String
    /// How far it goes, in metres.
    public var distanceMeters: Double

    public init(id: Int, text: String, distanceMeters: Double) {
        self.id = id
        self.text = text
        self.distanceMeters = distanceMeters
    }

    /// The distance for display, such as "450 ft".
    public var formattedDistance: String {
        DistanceFormat.string(meters: distanceMeters)
    }

    /// MOTIS's steps as instructions: steps along the same street (or along none) after the first fold into the one
    /// before, so a walk reads as its turns rather than every path segment.
    static func instructions(from steps: [StepInstruction]) -> [WalkInstruction] {
        var instructions: [WalkInstruction] = []
        var street: String?
        for step in steps {
            let name = step.streetName.trimmingCharacters(in: .whitespaces)
            let direction = step.relativeDirection.rawValue
            if let last = instructions.indices.last, direction == "CONTINUE", name.isEmpty || name == street {
                instructions[last].distanceMeters += step.distance
                continue
            }
            let text = text(direction: direction, street: name, isFirst: instructions.isEmpty)
            instructions.append(WalkInstruction(id: instructions.count, text: text, distanceMeters: step.distance))
            street = name.isEmpty ? street : name
        }
        return instructions
    }

    /// What each turn MOTIS names tells the rider to do, before the street it turns onto.
    private static let turns: [String: String] = [
        "LEFT": "Turn left",
        "HARD_LEFT": "Turn sharp left",
        "SLIGHTLY_LEFT": "Bear left",
        "RIGHT": "Turn right",
        "HARD_RIGHT": "Turn sharp right",
        "SLIGHTLY_RIGHT": "Bear right",
        "UTURN_LEFT": "Make a U-turn",
        "UTURN_RIGHT": "Make a U-turn",
        "CIRCLE_CLOCKWISE": "Go around the circle",
        "CIRCLE_COUNTERCLOCKWISE": "Go around the circle",
    ]

    private static func text(direction: String, street: String, isFirst: Bool) -> String {
        if let turn = turns[direction] {
            return street.isEmpty ? turn : "\(turn) onto \(street)"
        }
        switch direction {
        case "STAIRS": return "Take the stairs"
        case "ELEVATOR": return "Take the elevator"
        case _ where isFirst: return street.isEmpty ? "Start walking" : "Walk along \(street)"
        default: return street.isEmpty ? "Continue" : "Continue on \(street)"
        }
    }
}
