import Foundation

/// What the Apple Watch shows of the workout in progress, sent by the phone: the rest, the set to do with its setup,
/// and the sets after it. The watch only shows it and sends back what was pressed.
public struct WristState: Codable, Equatable, Sendable {
    public struct Line: Codable, Equatable, Sendable {
        public var entry: UUID
        public var set: UUID
        public var exercise: String
        /// "Set 2", "Warm-up", "Drop set".
        public var label: String
        /// "104 kg × 6": typed, else last time's.
        public var values: String
        /// What makes up the weight: "109 +2 pin 5", "20 10 a side".
        public var setup: String?
        /// "Seat 3 · Pad 4".
        public var settings: String

        public init(entry: UUID, set: UUID, exercise: String, label: String, values: String, setup: String?, settings: String) {
            self.entry = entry
            self.set = set
            self.exercise = exercise
            self.label = label
            self.values = values
            self.setup = setup
            self.settings = settings
        }
    }

    public var title: String
    public var start: Date
    public var restEnd: Date?
    public var restLength: Int
    /// The set to do now, then the next few.
    public var sets: [Line]
    public var sent: Date

    public init(title: String, start: Date, restEnd: Date?, restLength: Int, sets: [Line], sent: Date = Date()) {
        self.title = title
        self.start = start
        self.restEnd = restEnd
        self.restLength = restLength
        self.sets = sets
        self.sent = sent
    }

    /// Dates to the fraction of a second, so both show the same countdown.
    public func encoded() -> Data? { try? JSONEncoder().encode(self) }
    public static func decoded(_ data: Data) -> WristState? { try? JSONDecoder().decode(WristState.self, from: data) }

    /// Keys of the messages between the two.
    public enum Key {
        public static let state = "state"
        public static let none = "none"
        public static let action = "do"
        public static let entry = "entry"
        public static let set = "set"
        public static let rest = "rest"
        public static let by = "by"
    }

    /// What the watch sends back.
    public enum Action: String, Sendable {
        case done, adjust, skip
    }
}
