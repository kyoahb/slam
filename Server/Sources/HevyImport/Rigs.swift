import Foundation
import SlamCore

/// What the loadout lines of an exercise say about its rig, each checked against the logged weight.
struct Votes {
    /// Plates on a pin, or a slot plus extras.
    var stack = 0
    /// A plain total that fits any rig.
    var flat = 0
    /// Plates written once, on one side.
    var plates1 = 0
    /// Plates that count twice.
    var plates2 = 0
    /// Plates that count twice, with a bar.
    var bar = 0
    var dumbbell = 0

    var total: Int { stack + flat + plates1 + plates2 + bar + dumbbell }

    static func + (a: Votes, b: Votes) -> Votes {
        Votes(stack: a.stack + b.stack, flat: a.flat + b.flat, plates1: a.plates1 + b.plates1,
              plates2: a.plates2 + b.plates2, bar: a.bar + b.bar, dumbbell: a.dumbbell + b.dumbbell)
    }

    var summary: String {
        [("stack", stack), ("plain total", flat), ("one-side plates", plates1), ("two-side plates", plates2),
         ("bar", bar), ("dumbbell", dumbbell)].filter { $0.1 > 0 }.map { "\($0.0) \($0.1)" }.joined(separator: ", ")
    }
}

/// The equipment an exercise ends up with, and why that may be wrong.
struct Rigging {
    var equipment: Equipment
    var plateSides = 0
    var doubt: String?

    var key: String { "\(equipment.rawValue)/\(plateSides)" }
}

enum Rigs {
    static let eps = 0.011

    /// What one loadout says, given the logged weights of the sets it is about.
    static func vote(_ l: Loadout, kgs: [Double], rules: Rules) -> WritableKeyPath<Votes, Int>? {
        func hit(_ v: Double?) -> Bool {
            guard let v else { return false }
            return kgs.contains { abs($0 - v) < eps }
        }
        switch l.shape {
        case "L_PERSIDE":
            if kgs.contains(where: { rules.barCode(exact: $0 - l.plateTotal) != nil }) { return \.bar }
            if l.bar != nil, hit(l.total) { return \.bar }
            if hit(l.plateTotal) { return l.bar != nil ? \.bar : \.plates2 }
        case "L_COUNT":
            if hit(l.total) { return \.plates1 }
            if hit(l.total.map { 2 * $0 }) { return \.plates2 }
        case "L_BASE_COUNT", "L_DB":
            if hit(l.total) { return \.dumbbell }
        case "L_PIN":
            if hit(l.total) { return l.pinned || !l.plates.isEmpty ? \.stack : \.flat }
        case "L_SUM", "L_SPACED":
            if hit(l.total) { return l.pinned ? \.stack : \.flat }
            if l.shape == "L_SPACED" || l.addOn == nil, hit(l.total.map { 2 * $0 }) { return \.plates2 }
        default:
            if hit(l.total) { return \.flat }
        }
        return nil
    }

    /// Slam's equipment for an exercise from Hevy's, its name and what its notes say.
    static func decide(type: ExerciseType, hevy: String?, name: String, primary: Muscle, votes v: Votes,
                       rules: Rules) -> Rigging {
        let base = Map.equipment(hevy)
        let cable = word(name, "cable")
        if !type.hasKg {
            if type.hasTime && (base == .machine || primary == .cardio) { return Rigging(equipment: .cardio) }
            return Rigging(equipment: cable && base == .machine ? .cable : base)
        }
        let platesSeen = v.plates2 + v.bar > 0
        let barDoubt = "no note shows the plates; the bar is added to Hevy's weight"
        switch base {
        case .barbell:
            return Rigging(equipment: .barbell, doubt: platesSeen ? nil : barDoubt)
        case .dumbbell, .kettlebell, .band, .suspension:
            return Rigging(equipment: base)
        default:
            break
        }
        if plateLoadedName.matches(name) {
            let sides = v.plates2 + v.bar > v.plates1 ? 2 : (v.plates1 > 0 ? 1 : (tBar.matches(name) ? 1 : 2))
            return Rigging(equipment: .machine, plateSides: sides)
        }
        let barName = rules.bars.contains { $0.barbell && Rx($0.name, caseless: true).matches(name) }
            || (["barbell"] + rules.barWords).contains { word(name, $0) }
        if barName && !cable {
            return Rigging(equipment: .barbell, doubt: platesSeen ? nil : barDoubt)
        }
        let stackRig: Equipment = cable && [.machine, .other, .none].contains(base) ? .cable
            : (base == .machine || v.stack > 0 ? .machine : base)
        let options: [(Int, Rigging)] = [
            (v.stack + v.flat, Rigging(equipment: stackRig)),
            (v.plates1, Rigging(equipment: .machine, plateSides: 1)),
            (v.plates2 + v.bar, v.bar > 0 ? Rigging(equipment: .barbell) : Rigging(equipment: .machine, plateSides: 2)),
            (v.dumbbell, Rigging(equipment: .dumbbell)),
        ]
        let total = options.reduce(0) { $0 + $1.0 }
        guard total > 0 else { return Rigging(equipment: stackRig) }
        var best = options[0]
        for o in options.dropFirst() where o.0 > best.0 { best = o }
        var r = best.1
        if Double(best.0) / Double(total) < 0.75 {
            r.doubt = "the notes disagree (\(v.summary))"
        } else if r.key != Rigging(equipment: stackRig).key && total < 3 {
            r.doubt = "only \(total) note line\(total == 1 ? "" : "s") say\(total == 1 ? "s" : "") so (\(v.summary))"
        }
        return r
    }

    /// `w` as a whole word of `s`, ignoring case.
    static func word(_ s: String, _ w: String) -> Bool {
        s.range(of: "(?<![a-z])" + NSRegularExpression.escapedPattern(for: w.lowercased()) + "(?![a-z])",
                options: [.regularExpression, .caseInsensitive]) != nil
    }

    static let plateLoadedName = Rx(#"(?<![a-z])t[ -]?bar(?![a-z])|plate[ -]?loaded|(?<![a-z])smith(?![a-z])"#, caseless: true)
    static let tBar = Rx(#"(?<![a-z])t[ -]?bar(?![a-z])"#, caseless: true)
}

enum Names {
    /// Spacing fixed and words written all in lower case given capitals: "seated  leg curl ( lean)" as
    /// "Seated Leg Curl (Lean)".
    static func tidy(_ s: String) -> String {
        var t = s
        for (p, r) in [(#"\s+"#, " "), (#"\(\s+"#, "("), (#"\s+\)"#, ")"), (#"\(\s*\)"#, ""), (#"\s+"#, " ")] {
            t = t.replacingOccurrences(of: p, with: r, options: .regularExpression)
        }
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: " -,"))
        let m = NSMutableString(string: t)
        let words = lowerWord.all(t as NSString)
        for w in words.reversed() {
            let text = w.text
            if w.range.location > 0 && small.contains(text) { continue }
            m.replaceCharacters(in: w.range, with: text.prefix(1).uppercased() + text.dropFirst())
        }
        return m as String
    }

    /// The words of a name that say what the movement is.
    static func tokens(_ title: String, _ gyms: GymFinder, stop extra: [String]) -> Set<String> {
        let t = gyms.stripAll(title).lowercased()
            .replacingOccurrences(of: #"[()\-/,]"#, with: " ", options: .regularExpression)
        let stop = stopWords.union(extra.map { $0.lowercased() })
        return Set(t.split(separator: " ").map(String.init).filter { !stop.contains($0) }.map { synonyms[$0] ?? $0 })
    }

    /// The name says one arm or one leg at a time.
    static func onePerSide(_ title: String) -> Bool { uni.matches(title) }

    static let small: Set<String> = ["a", "an", "and", "at", "for", "in", "of", "on", "per", "the", "to", "with"]
    static let stopWords: Set<String> = ["machine", "cable", "the", "on", "with", "in", "of", "a", "gym", "group"]
    static let synonyms = ["uni": "unilateral", "single": "unilateral", "sa": "unilateral", "tricep": "triceps",
                           "ext": "extension"]
    /// Words that make another movement or another machine: a name that only adds one of these is not a rename.
    static let variantWords: Set<String> = [
        "close", "wide", "narrow", "neutral", "underhand", "overhand", "reverse", "pronated", "supinated",
        "incline", "decline", "flat", "high", "low", "front", "rear", "behind", "overhead", "standing", "seated",
        "lying", "kneeling", "hammer", "rope", "bar", "straight", "ez", "diverging", "converging", "iso",
        "unilateral", "assisted", "weighted", "smith", "plate", "loaded",
    ]
    private static let lowerWord = Rx(#"\b[a-z]+\b"#)
    private static let uni = Rx(#"\b(?:uni\w*|single\w*|sa|one[ -](?:arm|leg))\b"#, caseless: true)
}
