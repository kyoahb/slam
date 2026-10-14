import Foundation

public enum Previous {
    /// The latest finished workout entry for `exerciseId`, skipping `excluding` and anything from `before` on.
    /// `workouts` is newest first.
    public static func last(_ exerciseId: UUID, in workouts: [Workout], excluding: UUID? = nil,
                            before: Date? = nil) -> WorkoutExercise? {
        for w in workouts where w.id != excluding {
            if let before, w.start >= before { continue }
            if let e = w.exercises.first(where: { $0.exerciseId == exerciseId && !$0.sets.isEmpty }) { return e }
        }
        return nil
    }

    /// Pairs each set with last time's set of the same kind in the same position:
    /// warm-up 1 with warm-up 1, working set 2 with working set 2, drops with drops.
    /// Extra sets reuse the last one of their kind.
    public static func match(_ sets: [WorkSet], last: [WorkSet]) -> [WorkSet?] {
        let pools = Dictionary(grouping: last.filter { !$0.isEmpty }, by: \.kind)
        var seen: [SetKind: Int] = [:]
        return sets.map { s in
            let n = seen[s.kind, default: 0]
            seen[s.kind] = n + 1
            guard let pool = pools[s.kind], !pool.isEmpty else { return nil }
            return n < pool.count ? pool[n] : pool[pool.count - 1]
        }
    }

    /// W for warm-ups, D for drops, working sets numbered 1, 2, 3.
    public static func labels(_ sets: [WorkSet]) -> [String] {
        var n = 0
        return sets.map { s in
            switch s.kind {
            case .warmup: return "W"
            case .drop: return "D"
            case .normal:
                n += 1
                return String(n)
            }
        }
    }
}

public enum Rest {
    /// Seconds to rest after finishing `sets[index]`; nil means no timer (straight into a drop set).
    public static func after(_ index: Int, in sets: [WorkSet], settings: Settings) -> Int? {
        guard sets.indices.contains(index) else { return nil }
        if index + 1 < sets.count, sets[index + 1].kind == .drop { return nil }
        let seconds = sets[index].kind == .warmup ? settings.warmupRestSeconds : settings.restSeconds
        return seconds > 0 ? seconds : nil
    }
}
