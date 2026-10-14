import Foundation

/// How an exercise's weight is made up. It follows from the equipment, so nothing is set twice.
public enum Rig: Sendable {
    /// A pinned stack: its slots, an add-on switched on or off, plates hung on the gym pin.
    case stack
    /// Plates on a lever or sled, on one side or both.
    case plateLoaded
    /// A bar of fixed weight with plates on both ends: only the plates change.
    case barbell
    /// A dumbbell, with small plates clipped on.
    case dumbbell
    /// Just a number.
    case plain
}

/// The parts of a set's weight. `WorkSet.kg` stays the total.
public struct Load: Codable, Hashable, Sendable {
    /// The stack slot, the dumbbell, or the bar (a plate-loaded machine's own weight).
    public var base: Double
    /// The add-on when it is switched on, else 0.
    public var addOn: Double
    /// Plates on the pin, on the dumbbell, or on one side, heaviest first.
    public var plates: [Double]
    /// How many times the plates count: 2 on a bar or a two-sided machine.
    public var sides: Int

    public init(base: Double = 0, addOn: Double = 0, plates: [Double] = [], sides: Int = 1) {
        self.base = base
        self.addOn = addOn
        self.plates = plates
        self.sides = sides
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        base = try c.value(.base, 0)
        addOn = try c.value(.addOn, 0)
        plates = try c.value(.plates, [])
        sides = try c.value(.sides, 1)
    }

    public var total: Double { base + addOn + Double(sides) * plates.reduce(0, +) }

    /// The plates' share of the total.
    public var plateWeight: Double { Double(sides) * plates.reduce(0, +) }

    /// The parts in a few characters: "109 +2 pin 5", "22.5 +1", "20 10 a side". Nil when the total says it all.
    public func summary(_ rig: Rig) -> String? {
        let p = Plates.short(plates)
        switch rig {
        case .stack:
            guard addOn > 0 || !plates.isEmpty else { return nil }
            var parts = [Format.kg(base)]
            if addOn > 0 { parts.append("+" + Format.kg(addOn)) }
            if !plates.isEmpty { parts.append("pin " + p) }
            return parts.joined(separator: " ")
        case .dumbbell:
            guard !plates.isEmpty else { return nil }
            return ([Format.kg(base)] + plates.map { "+" + Format.kg($0) }).joined(separator: " ")
        case .barbell, .plateLoaded:
            guard !plates.isEmpty else { return nil }
            return sides > 1 ? p + " a side" : p
        case .plain:
            return nil
        }
    }

    /// A total with no parts kept (typed, or from Hevy) as the bar and plates it most likely was.
    public static func guess(_ kg: Double, _ ex: Exercise) -> Load {
        switch ex.rig {
        case .barbell, .plateLoaded:
            let sides = ex.sides
            let plates = Plates.make(max(0, (kg - ex.barWeight) / Double(sides)))
            // Whatever the plates cannot make stays in the base, so the total is unchanged.
            return Load(base: kg - Double(sides) * plates.reduce(0, +), plates: plates, sides: sides)
        default:
            return Load(base: kg, sides: ex.sides)
        }
    }
}

public enum Plates {
    /// Plates for bars, plate-loaded machines and the gym pin, heaviest first.
    public static let standard: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]
    /// Small plates that clip onto a dumbbell.
    public static let micro: [Double] = [0.5, 1, 1.25, 2.5]

    /// "20 20 20 20 5" as "4×20 5": three or more of a plate in a row are counted.
    public static func short(_ plates: [Double]) -> String {
        var parts: [String] = []
        var i = 0
        while i < plates.count {
            var n = 1
            while i + n < plates.count && plates[i + n] == plates[i] { n += 1 }
            parts += n >= 3 ? ["\(n)×" + Format.kg(plates[i])] : Array(repeating: Format.kg(plates[i]), count: n)
            i += n
        }
        return parts.joined(separator: " ")
    }

    /// `kg` as plates the way they are usually loaded: 20s first, heaviest first. Leftovers under 1.25 are dropped.
    public static func make(_ kg: Double) -> [Double] {
        var left = (kg * 100).rounded() / 100
        var out: [Double] = []
        for p in [20, 15, 10, 5, 2.5, 1.25] {
            while left >= p - 0.001 {
                out.append(p)
                left -= p
            }
        }
        return out
    }
}

public extension Exercise {
    var rig: Rig {
        guard type.hasKg else { return .plain }
        switch equipment {
        case .barbell: return .barbell
        case .dumbbell: return .dumbbell
        case .machine: return plateSides > 0 ? .plateLoaded : .stack
        case .cable: return .stack
        default: return .plain
        }
    }

    /// What the bar, or a plate-loaded machine, weighs on its own.
    var barWeight: Double { bar ?? (equipment == .barbell ? 20 : 0) }

    /// How many times each plate counts.
    var sides: Int {
        switch rig {
        case .barbell: 2
        case .plateLoaded: max(1, plateSides)
        default: 1
        }
    }

    /// A set before anything is picked: the bare bar or machine, nothing on the stack.
    var emptyLoad: Load {
        Load(base: rig == .barbell || rig == .plateLoaded ? barWeight : 0, sides: sides)
    }
}

public extension WorkSet {
    /// What the weight column shows: the slot or dumbbell when extras go on top of it, else the total.
    func shownKg(_ rig: Rig) -> Double? {
        guard let kg else { return nil }
        switch rig {
        case .stack, .dumbbell: return load?.base ?? kg
        default: return kg
        }
    }
}
