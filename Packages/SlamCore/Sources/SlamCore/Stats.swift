import Foundation

public enum Metric: String, CaseIterable, Sendable {
    case heaviest, e1rm, bestSet, session, reps, seconds, meters

    public var title: String {
        switch self {
        case .heaviest: "Heaviest Weight"
        case .e1rm: "One Rep Max"
        case .bestSet: "Best Set Volume"
        case .session: "Session Volume"
        case .reps: "Total Reps"
        case .seconds: "Duration"
        case .meters: "Distance"
        }
    }

    public static func available(for type: ExerciseType) -> [Metric] {
        var out: [Metric] = []
        if type.hasKg && type != .assistedBodyweight {
            out.append(.heaviest)
            if type.hasReps { out += [.e1rm, .bestSet, .session] }
        }
        if type.hasReps { out.append(.reps) }
        if type.hasTime { out.append(.seconds) }
        if type.hasDistance { out.append(.meters) }
        return out
    }
}

public struct Point: Hashable, Sendable, Identifiable {
    public var id: UUID { workoutId }
    public var date: Date
    public var value: Double
    public var workoutId: UUID
    public var gymId: UUID?
}

public struct Week: Hashable, Sendable, Identifiable {
    public var id: Date { start }
    public var start: Date
    public var volume: Double = 0
    public var sets = 0
    public var reps = 0
    public var workouts = 0
    public var seconds: TimeInterval = 0
}

public enum Stats {
    public static func volume(_ w: Workout, _ exercises: [UUID: Exercise]) -> Double {
        w.exercises.reduce(0) { sum, e in
            let type = exercises[e.exerciseId]?.type ?? .weightReps
            return sum + SetMath.working(e).reduce(0) { $0 + SetMath.volume($1, type) }
        }
    }

    public static func sets(_ w: Workout) -> Int {
        w.exercises.reduce(0) { $0 + $1.sets.filter(\.done).count }
    }

    public static func reps(_ w: Workout) -> Int {
        w.exercises.reduce(0) { $0 + SetMath.working($1).reduce(0) { $0 + SetMath.reps($1) } }
    }

    public static func mondayCalendar() -> Calendar {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = .current
        return c
    }

    public static func weekStart(_ date: Date, _ calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    /// Every week from the first workout to `now`, empty weeks included, oldest first.
    public static func weeks(_ workouts: [Workout], _ exercises: [UUID: Exercise], now: Date = Date(),
                             calendar: Calendar = mondayCalendar()) -> [Week] {
        guard let first = workouts.map(\.start).min() else { return [] }
        var byStart: [Date: Week] = [:]
        for w in workouts {
            let s = weekStart(w.start, calendar)
            var week = byStart[s] ?? Week(start: s)
            week.volume += volume(w, exercises)
            week.sets += sets(w)
            week.reps += reps(w)
            week.workouts += 1
            week.seconds += w.duration
            byStart[s] = week
        }
        var out: [Week] = []
        var cursor = weekStart(first, calendar)
        let last = weekStart(max(now, workouts.map(\.start).max() ?? now), calendar)
        while cursor <= last {
            out.append(byStart[cursor] ?? Week(start: cursor))
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor) else { break }
            cursor = next
        }
        return out
    }

    /// Working sets per primary muscle, most first.
    public static func setsPerMuscle(_ workouts: [Workout], _ exercises: [UUID: Exercise],
                                     from: Date, to: Date) -> [(muscle: Muscle, sets: Int)] {
        var counts: [Muscle: Int] = [:]
        for w in workouts where w.start >= from && w.start < to {
            for e in w.exercises {
                let muscle = exercises[e.exerciseId]?.primary ?? .other
                counts[muscle, default: 0] += SetMath.working(e).count
            }
        }
        return counts.filter { $0.value > 0 }
            .map { (muscle: $0.key, sets: $0.value) }
            .sorted { $0.sets != $1.sets ? $0.sets > $1.sets : $0.muscle.title < $1.muscle.title }
    }

    /// One point per session of an exercise, oldest first.
    public static func series(_ exerciseId: UUID, _ workouts: [Workout], metric: Metric,
                              type: ExerciseType) -> [Point] {
        var out: [Point] = []
        for w in workouts.sorted(by: { $0.start < $1.start }) {
            let sets = w.exercises.filter { $0.exerciseId == exerciseId }.flatMap(SetMath.working)
            guard !sets.isEmpty else { continue }
            let value: Double
            switch metric {
            case .heaviest: value = sets.compactMap(\.kg).max() ?? 0
            case .e1rm: value = sets.compactMap(SetMath.e1rm).max() ?? 0
            case .bestSet: value = sets.map { SetMath.volume($0, type) }.max() ?? 0
            case .session: value = sets.reduce(0) { $0 + SetMath.volume($1, type) }
            case .reps: value = Double(sets.reduce(0) { $0 + SetMath.reps($1) })
            case .seconds: value = Double(sets.reduce(0) { $0 + ($1.seconds ?? 0) })
            case .meters: value = sets.reduce(0) { $0 + ($1.meters ?? 0) }
            }
            if value > 0 { out.append(Point(date: w.start, value: value, workoutId: w.id, gymId: w.gymId)) }
        }
        return out
    }

    /// Weeks in a row with at least one workout, counting back from this week (or last week, if this one is still empty).
    public static func weekStreak(_ dates: [Date], now: Date = Date(), calendar: Calendar = mondayCalendar()) -> Int {
        let weeks = Set(dates.map { weekStart($0, calendar) })
        var cursor = weekStart(now, calendar)
        if !weeks.contains(cursor) {
            guard let prev = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else { return 0 }
            cursor = prev
        }
        var n = 0
        while weeks.contains(cursor) {
            n += 1
            guard let prev = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return n
    }

    /// Whole days since the last workout.
    public static func restDays(_ dates: [Date], now: Date = Date(), calendar: Calendar = mondayCalendar()) -> Int {
        guard let last = dates.max() else { return 0 }
        let a = calendar.startOfDay(for: last), b = calendar.startOfDay(for: now)
        return max(0, calendar.dateComponents([.day], from: a, to: b).day ?? 0)
    }
}
