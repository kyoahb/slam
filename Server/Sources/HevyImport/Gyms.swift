import Foundation
import SlamCore

/// Which gym a workout was at, and which gym an exercise name was made for.
struct GymFinder {
    enum Basis: String, CaseIterable {
        case text = "named in the title or description"
        case exercises = "gym-named exercises"
        case stretching = "stretching only"
        case timeline = "date"
        case none = "nothing to go by"
    }

    let rules: Rules
    private let text: [(Int, Rx)]
    private let exercise: [(Int, Rx)]
    private let markers: [(Int, Rx)]

    init(_ rules: Rules) {
        self.rules = rules
        func compile(_ pick: (Rules.Gym) -> [String]) -> [(Int, Rx)] {
            rules.gyms.indices.flatMap { i in pick(rules.gyms[i]).map { (i, Rx($0, caseless: true)) } }
        }
        text = compile(\.text)
        exercise = compile(\.exercise)
        markers = compile(\.marker)
    }

    /// The rules' gym for a name, nil when no gym is called that.
    func index(_ name: String?) -> Int? {
        guard let name else { return nil }
        return rules.gyms.firstIndex { $0.name == name }
    }

    /// The gym an exercise name was made for.
    func exerciseGym(_ title: String) -> Int? {
        exercise.first { $0.1.matches(title) }?.0
    }

    /// The gym a workout was at (an index into `rules.gyms`, whose name is nil for an unknown gym).
    func workoutGym(_ w: Hevy.Workout, _ templates: [String: Hevy.Template]) -> (Int?, Basis) {
        let words = w.title + " \n" + (w.description ?? "")
        if let hit = text.first(where: { $0.1.matches(words) }) { return (hit.0, .text) }
        var counts: [Int: Int] = [:]
        var order: [Int] = []
        for e in w.exercises {
            guard let g = exerciseGym(e.title) else { continue }
            if counts[g] == nil { order.append(g) }
            counts[g, default: 0] += 1
        }
        var best: Int?
        for g in order where best.map({ counts[g]! > counts[$0]! }) ?? true { best = g }
        if let best { return (best, .exercises) }
        if !w.exercises.isEmpty, w.exercises.allSatisfy({ templates[$0.exerciseTemplateId]?.type == "duration" }) {
            return (nil, .stretching)
        }
        if let g = index(rules.timelineGym(w.day)) { return (g, .timeline) }
        return (nil, .none)
    }

    /// Removes the parts of a name that only name a gym; returns the gym they named.
    func stripMarkers(_ title: String) -> (String, Int?) {
        var s = title
        var gym: Int?
        for (i, rx) in markers where rx.matches(s) {
            s = rx.re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: " ")
            gym = gym ?? i
        }
        return (s, gym)
    }

    /// Removes every gym mark from a name, for comparing names.
    func stripAll(_ title: String) -> String {
        var s = stripMarkers(title).0
        for (_, rx) in exercise {
            s = rx.re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: " ")
        }
        return s
    }

    func addOns(_ gym: Int?) -> Set<Double> {
        Set(gym.flatMap { rules.gyms[$0].addOns } ?? rules.addOns)
    }

    func name(_ gym: Int?) -> String? { gym.flatMap { rules.gyms[$0].name } }
}

/// Hevy's words for things, in Slam's terms.
enum Map {
    static func type(_ s: String) -> ExerciseType {
        switch s {
        case "weight_reps": .weightReps
        case "reps_only": .repsOnly
        case "bodyweight_reps", "bodyweight_weighted": .bodyweightReps
        case "bodyweight_assisted", "assisted_bodyweight": .assistedBodyweight
        case "weight_duration": .weightDuration
        case "distance_duration": .distanceDuration
        case "short_distance_weight": .shortDistanceWeight
        case "duration", "floors_duration", "steps_duration": .duration
        default: .weightReps
        }
    }

    static func equipment(_ s: String?) -> Equipment {
        switch s {
        case "barbell": .barbell
        case "dumbbell": .dumbbell
        case "kettlebell": .kettlebell
        case "machine": .machine
        case "plate": .plate
        case "resistance_band": .band
        case "suspension": .suspension
        case "none": Equipment.none
        default: .other
        }
    }

    static func muscle(_ s: String?) -> Muscle {
        guard let s else { return .other }
        let camel = s.split(separator: "_").enumerated()
            .map { $0.offset == 0 ? String($0.element) : $0.element.capitalized }.joined()
        return Muscle(rawValue: camel) ?? .other
    }

    static func kind(_ s: String) -> SetKind {
        switch s {
        case "warmup": .warmup
        case "dropset": .drop
        default: .normal
        }
    }
}
