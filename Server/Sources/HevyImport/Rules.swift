import Foundation

/// What the importer knows about one person: their gyms, how their notes are written, their misspellings.
/// The real file sits next to the import output and never in the repo. Empty rules still import; they just
/// know no gyms and only plain English.
public struct Rules: Codable, Sendable {
    /// A gym, or an unknown one when `name` is nil, and how to tell a workout or an exercise was there.
    public struct Gym: Codable, Sendable {
        public var name: String?
        /// Patterns for the workout title and description.
        public var text: [String]
        /// Patterns for exercise names made for this gym.
        public var exercise: [String]
        /// Parts of an exercise name that only name the gym; they are dropped from the Slam name.
        public var marker: [String]
        /// Who made this gym's named machines. It replaces the marker in the name.
        public var brand: String?
        /// Every machine used only at this gym is by `brand`.
        public var brandAllMachines: Bool
        /// The add-on weights of this gym's stacks.
        public var addOns: [Double]?

        public init(name: String?, text: [String] = [], exercise: [String] = [], marker: [String] = [],
                    brand: String? = nil, brandAllMachines: Bool = false, addOns: [Double]? = nil) {
            self.name = name
            self.text = text
            self.exercise = exercise
            self.marker = marker
            self.brand = brand
            self.brandAllMachines = brandAllMachines
            self.addOns = addOns
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decodeIfPresent(String.self, forKey: .name)
            text = try c.decodeIfPresent([String].self, forKey: .text) ?? []
            exercise = try c.decodeIfPresent([String].self, forKey: .exercise) ?? []
            marker = try c.decodeIfPresent([String].self, forKey: .marker) ?? []
            brand = try c.decodeIfPresent(String.self, forKey: .brand)
            brandAllMachines = try c.decodeIfPresent(Bool.self, forKey: .brandAllMachines) ?? false
            addOns = try c.decodeIfPresent([Double].self, forKey: .addOns)
        }
    }

    /// From this date (yyyy-MM-dd) on, workouts with nothing else to go by were at `gym`.
    public struct Period: Codable, Sendable {
        public var from: String
        public var gym: String

        public init(from: String, gym: String) {
            self.from = from
            self.gym = gym
        }
    }

    /// A bar of known weight for exercises whose name matches `name`.
    public struct Bar: Codable, Sendable {
        public var name: String
        public var kg: Double
        /// The name alone makes the exercise a barbell one.
        public var barbell: Bool

        public init(name: String, kg: Double, barbell: Bool = false) {
            self.name = name
            self.kg = kg
            self.barbell = barbell
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            kg = try c.decode(Double.self, forKey: .kg)
            barbell = try c.decodeIfPresent(Bool.self, forKey: .barbell) ?? false
        }
    }

    /// In the order they are tried.
    public var gyms: [Gym]
    public var timeline: [Period]
    /// Where new workouts are logged.
    public var currentGym: String?
    /// Add-on weights at gyms that list none.
    public var addOns: [Double]
    public var bars: [Bar]
    /// A logged weight's last decimals that stand for the bar: "0.3" for a 30 kg bar, say.
    public var barCodes: [String: Double]
    /// Name words that mean a free bar, besides "barbell".
    public var barWords: [String]
    /// Misspellings and what they mean, replaced before a line is read.
    public var aliases: [String: String]
    /// Words for the gym pin plates hang on, besides "pin".
    public var pinWords: [String]
    /// Slips of the pin word, read only right after the plates' bracket.
    public var pinTypos: [String]
    /// Names of seat and pad settings, besides the plain English ones.
    public var settingWords: [String]
    /// A setting word and the name Slam shows for it.
    public var settingNames: [String: String]
    /// Counters written after the effort ("3c"); they are dropped.
    public var counters: [String]
    /// Patterns for phrases that stay in the note exactly as written.
    public var keep: [String]
    /// Patterns for plans ("next time ..."); a loadout on such a line is not today's weight.
    public var plans: [String]
    /// Words that say nothing about the movement, ignored when comparing names.
    public var nameStopWords: [String]
    /// The name for a setting position written with no name.
    public var defaultSetting: String

    public init(gyms: [Gym] = [], timeline: [Period] = [], currentGym: String? = nil, addOns: [Double] = [],
                bars: [Bar] = [], barCodes: [String: Double] = [:], barWords: [String] = [],
                aliases: [String: String] = [:], pinWords: [String] = [], pinTypos: [String] = [],
                settingWords: [String] = [], settingNames: [String: String] = [:], counters: [String] = [],
                keep: [String] = [], plans: [String] = [], nameStopWords: [String] = [],
                defaultSetting: String = "Position") {
        self.gyms = gyms
        self.timeline = timeline
        self.currentGym = currentGym
        self.addOns = addOns
        self.bars = bars
        self.barCodes = barCodes
        self.barWords = barWords
        self.aliases = aliases
        self.pinWords = pinWords
        self.pinTypos = pinTypos
        self.settingWords = settingWords
        self.settingNames = settingNames
        self.counters = counters
        self.keep = keep
        self.plans = plans
        self.nameStopWords = nameStopWords
        self.defaultSetting = defaultSetting
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gyms = try c.decodeIfPresent([Gym].self, forKey: .gyms) ?? []
        timeline = try c.decodeIfPresent([Period].self, forKey: .timeline) ?? []
        currentGym = try c.decodeIfPresent(String.self, forKey: .currentGym)
        addOns = try c.decodeIfPresent([Double].self, forKey: .addOns) ?? []
        bars = try c.decodeIfPresent([Bar].self, forKey: .bars) ?? []
        barCodes = try c.decodeIfPresent([String: Double].self, forKey: .barCodes) ?? [:]
        barWords = try c.decodeIfPresent([String].self, forKey: .barWords) ?? []
        aliases = try c.decodeIfPresent([String: String].self, forKey: .aliases) ?? [:]
        pinWords = try c.decodeIfPresent([String].self, forKey: .pinWords) ?? []
        pinTypos = try c.decodeIfPresent([String].self, forKey: .pinTypos) ?? []
        settingWords = try c.decodeIfPresent([String].self, forKey: .settingWords) ?? []
        settingNames = try c.decodeIfPresent([String: String].self, forKey: .settingNames) ?? [:]
        counters = try c.decodeIfPresent([String].self, forKey: .counters) ?? []
        keep = try c.decodeIfPresent([String].self, forKey: .keep) ?? []
        plans = try c.decodeIfPresent([String].self, forKey: .plans) ?? []
        nameStopWords = try c.decodeIfPresent([String].self, forKey: .nameStopWords) ?? []
        defaultSetting = try c.decodeIfPresent(String.self, forKey: .defaultSetting) ?? "Position"
    }

    /// The rules in `url`, or nil when there is no such file.
    public static func load(_ url: URL) throws -> Rules? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(Rules.self, from: Data(contentsOf: url))
    }

    /// The gym the timeline gives for a day.
    func timelineGym(_ day: String) -> String? {
        timeline.sorted { $0.from < $1.from }.last { $0.from <= day }?.gym
    }

    /// The bar a weight's decimals stand for, and the decimals.
    func barCode(_ kg: Double) -> (code: Double, bar: Double)? {
        let frac = ((kg - (kg / 0.5).rounded(.down) * 0.5) * 1000).rounded() / 1000
        return barCode(exact: frac)
    }

    func barCode(exact v: Double) -> (code: Double, bar: Double)? {
        let r = (v * 1000).rounded() / 1000
        for (k, bar) in barCodes {
            if let c = Double(k), abs(c - r) < 0.0005 { return (c, bar) }
        }
        return nil
    }
}
