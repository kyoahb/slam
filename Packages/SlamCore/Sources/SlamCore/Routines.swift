import Foundation

public extension Workout {
    /// A new workout from a routine: same exercises and set types, routine settings carried over,
    /// per-workout settings as they were last time. Values stay empty so last time shows as placeholders.
    static func from(_ routine: Routine, exercises: [UUID: Exercise], history: [Workout], gymId: UUID?,
                     now: Date = Date()) -> Workout {
        let entries = routine.exercises.map { r -> WorkoutExercise in
            var e = WorkoutExercise(exerciseId: r.exerciseId, settings: r.settings, supersetId: r.supersetId)
            e.sets = r.sets.map { WorkSet(kind: $0.kind) }
            if e.sets.isEmpty { e.sets = [WorkSet()] }
            e.carrySettings(exercises[r.exerciseId], last: Previous.last(r.exerciseId, in: history))
            return e
        }
        return Workout(title: routine.name, start: now, gymId: gymId, routineId: routine.id, exercises: entries)
    }
}

public extension WorkoutExercise {
    /// Per-workout settings (incline, level) start as they were last time.
    mutating func carrySettings(_ exercise: Exercise?, last: WorkoutExercise?) {
        guard let exercise, let last else { return }
        for c in exercise.settings where c.perWorkout && self[setting: c.id].isEmpty {
            self[setting: c.id] = last[setting: c.id]
        }
    }

    /// A new entry for an exercise added mid-workout: as many sets as last time, same types.
    static func adding(_ exercise: Exercise, last: WorkoutExercise?) -> WorkoutExercise {
        var e = WorkoutExercise(exerciseId: exercise.id)
        e.sets = last?.sets.map { WorkSet(kind: $0.kind) } ?? [WorkSet()]
        if e.sets.isEmpty { e.sets = [WorkSet()] }
        e.carrySettings(exercise, last: last)
        return e
    }
}

public enum RoutineDiff {
    /// What the workout changed against its routine, or nil when nothing worth saving did.
    public static func describe(_ w: Workout, _ r: Routine, _ exercises: [UUID: Exercise]) -> String? {
        let a = r.exercises.map(\.exerciseId), b = w.exercises.map(\.exerciseId)
        var parts: [String] = []
        let added = b.filter { !a.contains($0) }.count
        let removed = a.filter { !b.contains($0) }.count
        if added > 0 { parts.append(added == 1 ? "You added an exercise." : "You added \(added) exercises.") }
        if removed > 0 { parts.append(removed == 1 ? "You removed an exercise." : "You removed \(removed) exercises.") }
        if b.filter(a.contains) != a.filter(b.contains) { parts.append("You reordered your exercises.") }
        let both = Set(a).intersection(b)
        if both.contains(where: { id in kinds(r.exercises, id) != kinds(w.exercises, id) }) {
            parts.append("You changed sets.")
        }
        if both.contains(where: { id in routineSettings(r.exercises, id, exercises) != routineSettings(w.exercises, id, exercises) }) {
            parts.append("You changed machine settings.")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// The routine rebuilt from the workout: its order, its set types, its machine settings.
    /// Long-term notes stay with their exercises.
    public static func apply(_ w: Workout, to r: Routine, _ exercises: [UUID: Exercise]) -> Routine {
        var routine = r
        var pool = r.exercises
        routine.exercises = w.exercises.map { e in
            var entry: WorkoutExercise
            if let i = pool.firstIndex(where: { $0.exerciseId == e.exerciseId }) {
                entry = pool.remove(at: i)
            } else {
                entry = WorkoutExercise(exerciseId: e.exerciseId)
            }
            let sets = e.sets.filter { $0.done || !$0.isEmpty }
            entry.sets = (sets.isEmpty ? e.sets : sets).map { WorkSet(kind: $0.kind) }
            entry.settings = [:]
            for c in exercises[e.exerciseId]?.settings ?? [] where !c.perWorkout {
                entry[setting: c.id] = e[setting: c.id]
            }
            entry.supersetId = e.supersetId
            return entry
        }
        return routine
    }

    static func kinds(_ list: [WorkoutExercise], _ id: UUID) -> [SetKind] {
        guard let e = list.first(where: { $0.exerciseId == id }) else { return [] }
        let kept = e.sets.filter { $0.done || !$0.isEmpty }
        return (kept.isEmpty ? e.sets : kept).map(\.kind)
    }

    static func routineSettings(_ list: [WorkoutExercise], _ id: UUID, _ exercises: [UUID: Exercise]) -> [String] {
        guard let e = list.first(where: { $0.exerciseId == id }) else { return [] }
        return (exercises[id]?.settings ?? []).filter { !$0.perWorkout }.map { e[setting: $0.id] }
    }
}

public extension Routine {
    /// A routine from a finished workout ("Save as Routine").
    static func from(_ w: Workout, name: String, exercises: [UUID: Exercise]) -> Routine {
        RoutineDiff.apply(w, to: Routine(name: name), exercises)
    }
}
