import Foundation

public enum SetMath {
    /// kg × reps, both sides counted on a unilateral exercise. Zero when there is no weight to count.
    public static func volume(_ s: WorkSet, _ type: ExerciseType = .weightReps) -> Double {
        guard type != .assistedBodyweight, let kg = s.kg, kg > 0 else { return 0 }
        return kg * Double(reps(s))
    }

    public static func reps(_ s: WorkSet) -> Int { (s.reps ?? 0) + (s.repsR ?? 0) }

    /// Estimated one-rep max (Epley, counting reps in reserve), best side.
    public static func e1rm(_ s: WorkSet) -> Double? {
        guard let kg = s.kg, kg > 0 else { return nil }
        let sides: [Double] = [(s.reps, s.rir), (s.repsR, s.rirR)].compactMap { pair in
            guard let r = pair.0, r > 0 else { return nil }
            let total = r + (pair.1 ?? 0)
            return total <= 1 ? kg : kg * (1 + Double(total) / 30)
        }
        return sides.max()
    }

    /// How good a set is, for comparing like with like: e1RM, else reps, else time, else distance.
    public static func score(_ s: WorkSet, _ type: ExerciseType) -> Double {
        if type.hasKg, type != .assistedBodyweight, let e = e1rm(s) { return e }
        if type == .assistedBodyweight, let kg = s.kg, reps(s) > 0 {
            return Double(reps(s) + (s.rir ?? 0)) * 1000 - kg
        }
        if type.hasReps { return Double(reps(s) + (s.rir ?? 0) + (s.rirR ?? 0)) }
        if type.hasDistance, let m = s.meters { return m }
        return Double(s.seconds ?? 0)
    }

    /// Finished sets that count: everything but warm-ups.
    public static func working(_ e: WorkoutExercise) -> [WorkSet] {
        e.sets.filter { $0.done && $0.kind != .warmup && !$0.isEmpty }
    }

    /// Finished working sets in order, drops left out, for set-by-set comparisons.
    public static func numbered(_ e: WorkoutExercise) -> [WorkSet] {
        e.sets.filter { $0.done && $0.kind == .normal && !$0.isEmpty }
    }
}

public enum RecordKind: Hashable, Sendable {
    case heaviest, e1rm, setVolume, sessionVolume, reps, seconds, meters
    /// Best working set at this position (0 = set 1), even when not the best set overall.
    case set(Int)

    public var title: String {
        switch self {
        case .heaviest: "Heaviest Weight"
        case .e1rm: "Best 1RM"
        case .setVolume: "Best Set Volume"
        case .sessionVolume: "Best Session Volume"
        case .reps: "Most Reps"
        case .seconds: "Longest Time"
        case .meters: "Longest Distance"
        case .set(let i): "Best Set \(i + 1)"
        }
    }
}

public struct Record: Hashable, Sendable {
    public var kind: RecordKind
    public var setId: UUID?
    public var exerciseId: UUID?

    public init(kind: RecordKind, setId: UUID? = nil, exerciseId: UUID? = nil) {
        self.kind = kind
        self.setId = setId
        self.exerciseId = exerciseId
    }
}

/// The best numbers so far for one exercise.
public struct Bests: Hashable, Sendable {
    public var type: ExerciseType
    public var sessions = 0
    public var heaviest: WorkSet?
    public var e1rm: WorkSet?
    public var setVolume: WorkSet?
    public var sessionVolume: Double = 0
    public var reps: WorkSet?
    public var seconds: WorkSet?
    public var meters: WorkSet?
    /// Best set at each working-set position.
    public var bySet: [WorkSet] = []

    public init(type: ExerciseType) { self.type = type }

    public mutating func add(_ e: WorkoutExercise) {
        let sets = SetMath.working(e)
        guard !sets.isEmpty else { return }
        sessions += 1
        for s in sets {
            if (s.kg ?? 0) > (heaviest?.kg ?? 0) { heaviest = s }
            if (SetMath.e1rm(s) ?? 0) > (e1rm.flatMap(SetMath.e1rm) ?? 0) { e1rm = s }
            if SetMath.volume(s, type) > setVolume.map({ SetMath.volume($0, type) }) ?? 0 { setVolume = s }
            if SetMath.reps(s) > reps.map(SetMath.reps) ?? 0 { reps = s }
            if (s.seconds ?? 0) > (seconds?.seconds ?? 0) { seconds = s }
            if (s.meters ?? 0) > (meters?.meters ?? 0) { meters = s }
        }
        sessionVolume = max(sessionVolume, sets.reduce(0) { $0 + SetMath.volume($1, type) })
        for (i, s) in SetMath.numbered(e).enumerated() {
            if i < bySet.count {
                if SetMath.score(s, type) > SetMath.score(bySet[i], type) { bySet[i] = s }
            } else {
                bySet.append(s)
            }
        }
    }

    /// What `e` beats. Nothing on the first session: there is nothing to beat yet.
    public func records(_ e: WorkoutExercise) -> [Record] {
        guard sessions > 0 else { return [] }
        let sets = SetMath.working(e)
        guard !sets.isEmpty else { return [] }
        var out: [Record] = []
        func beat(_ kind: RecordKind, _ value: (WorkSet) -> Double, _ old: WorkSet?) {
            guard let top = sets.max(by: { value($0) < value($1) }), value(top) > 0,
                  value(top) > (old.map(value) ?? 0) + 0.0001 else { return }
            out.append(Record(kind: kind, setId: top.id, exerciseId: e.exerciseId))
        }
        if type.hasKg && type != .assistedBodyweight {
            beat(.heaviest, { $0.kg ?? 0 }, heaviest)
            if type.hasReps {
                beat(.e1rm, { SetMath.e1rm($0) ?? 0 }, e1rm)
                beat(.setVolume, { SetMath.volume($0, type) }, setVolume)
                let total = sets.reduce(0) { $0 + SetMath.volume($1, type) }
                if total > sessionVolume + 0.0001 { out.append(Record(kind: .sessionVolume, exerciseId: e.exerciseId)) }
            }
        } else if type.hasReps {
            beat(.reps, { Double(SetMath.reps($0)) }, reps)
        }
        if type.hasTime { beat(.seconds, { Double($0.seconds ?? 0) }, seconds) }
        if type.hasDistance { beat(.meters, { $0.meters ?? 0 }, meters) }
        let overall = Set(out.compactMap(\.setId))
        for (i, s) in SetMath.numbered(e).enumerated() where i < bySet.count && !overall.contains(s.id) {
            if SetMath.score(s, type) > SetMath.score(bySet[i], type) + 0.0001 {
                out.append(Record(kind: .set(i), setId: s.id, exerciseId: e.exerciseId))
            }
        }
        return out
    }
}

/// A record just made, as the banner tells it: the best before, and the new one.
public struct LiveRecord: Hashable, Sendable {
    public var kind: RecordKind
    public var before: Double?
    public var after: Double
    /// For set-by-set records: the best set at that position before, and the new set.
    public var beforeSet: WorkSet?
    public var afterSet: WorkSet?
}

public extension Bests {
    /// The number a record kind is judged on, for one set.
    static func measure(_ kind: RecordKind, _ s: WorkSet, _ type: ExerciseType) -> Double {
        switch kind {
        case .heaviest: s.kg ?? 0
        case .e1rm: SetMath.e1rm(s) ?? 0
        case .setVolume: SetMath.volume(s, type)
        case .reps: Double(SetMath.reps(s))
        case .seconds: Double(s.seconds ?? 0)
        case .meters: s.meters ?? 0
        case .sessionVolume, .set: SetMath.score(s, type)
        }
    }

    private func best(_ kind: RecordKind) -> WorkSet? {
        switch kind {
        case .heaviest: heaviest
        case .e1rm: e1rm
        case .setVolume: setVolume
        case .reps: reps
        case .seconds: seconds
        case .meters: meters
        case .sessionVolume: nil
        case .set(let i): bySet.indices.contains(i) ? bySet[i] : nil
        }
    }

    /// Records the set `setId` just made, with `e` the exercise so far today. Earlier sets today count as "before".
    func news(_ e: WorkoutExercise, set setId: UUID) -> [LiveRecord] {
        var old = e
        for i in old.sets.indices where old.sets[i].id == setId { old.sets[i].done = false }
        let had = Set(records(old))
        let earlier = SetMath.working(old)
        return records(e).filter { !had.contains($0) && ($0.setId == setId || $0.setId == nil) }.compactMap { r in
            switch r.kind {
            case .sessionVolume:
                let total = SetMath.working(e).reduce(0) { $0 + SetMath.volume($1, type) }
                return LiveRecord(kind: r.kind, before: sessionVolume, after: total)
            case .set:
                guard let now = e.sets.first(where: { $0.id == setId }) else { return nil }
                return LiveRecord(kind: r.kind, before: nil, after: Self.measure(r.kind, now, type),
                                  beforeSet: best(r.kind), afterSet: now)
            default:
                guard let now = e.sets.first(where: { $0.id == setId }) else { return nil }
                let then = ([best(r.kind)].compactMap { $0 } + earlier).map { Self.measure(r.kind, $0, type) }.max()
                return LiveRecord(kind: r.kind, before: then.flatMap { $0 > 0 ? $0 : nil },
                                  after: Self.measure(r.kind, now, type), afterSet: now)
            }
        }
    }
}

public enum Records {
    /// Records set in each workout, checked against everything logged before it.
    public static func all(_ workouts: [Workout], exercises: [UUID: Exercise]) -> [UUID: [Record]] {
        var bests: [UUID: Bests] = [:]
        var out: [UUID: [Record]] = [:]
        for w in workouts.sorted(by: { $0.start < $1.start }) {
            var found: [Record] = []
            for e in w.exercises {
                let type = exercises[e.exerciseId]?.type ?? .weightReps
                var b = bests[e.exerciseId] ?? Bests(type: type)
                found += b.records(e)
                b.add(e)
                bests[e.exerciseId] = b
            }
            out[w.id] = found
        }
        return out
    }

    public static func bests(_ exerciseId: UUID, type: ExerciseType, in workouts: [Workout],
                             excluding: UUID? = nil, before: Date? = nil) -> Bests {
        var b = Bests(type: type)
        for w in workouts.sorted(by: { $0.start < $1.start }) where w.id != excluding {
            if let before, w.start >= before { continue }
            for e in w.exercises where e.exerciseId == exerciseId { b.add(e) }
        }
        return b
    }
}

public enum Trend: Sendable {
    case up, same, down
}

public extension Trend {
    /// Set by set against last time: more sets better than worse is up.
    static func compare(_ e: WorkoutExercise, last: WorkoutExercise?, type: ExerciseType) -> Trend? {
        guard let last else { return nil }
        let now = SetMath.numbered(e), then = SetMath.numbered(last)
        let n = min(now.count, then.count)
        guard n > 0 else { return nil }
        var score = 0
        for i in 0..<n {
            let a = SetMath.score(now[i], type), b = SetMath.score(then[i], type)
            if a > b + 0.0001 { score += 1 } else if a < b - 0.0001 { score -= 1 }
        }
        if score == 0 { score = now.count - then.count }
        return score > 0 ? .up : score < 0 ? .down : .same
    }
}
