import Foundation

/// An Apple Watch workout as Health saved it.
public struct WatchLink: Codable, Hashable, Sendable {
    /// Health's id for the workout, so it is linked only once.
    public var id: UUID
    public var start: Date
    public var end: Date
    public var meters: Double?
    public var kcal: Double?
    /// Average beats per minute.
    public var heartRate: Double?

    public init(id: UUID, start: Date, end: Date, meters: Double? = nil, kcal: Double? = nil, heartRate: Double? = nil) {
        self.id = id
        self.start = start
        self.end = end
        self.meters = meters
        self.kcal = kcal
        self.heartRate = heartRate
    }

    public var seconds: Int { Int(end.timeIntervalSince(start).rounded()) }
}

/// The Watch workouts a cardio exercise can be.
public enum WatchActivity: String, Codable, CaseIterable, Sendable {
    case elliptical, stairs, rowing, cycling, running, walking, swimming
}

public extension Exercise {
    /// Read from the name: "Precor Elliptical" is an elliptical, a treadmill a walk or a run.
    var watchActivities: [WatchActivity] {
        guard type == .duration || type == .distanceDuration else { return [] }
        let n = name.lowercased()
        let words: [([String], [WatchActivity])] = [
            (["elliptical", "cross trainer", "crosstrainer"], [.elliptical]),
            (["stair", "step"], [.stairs]),
            (["row"], [.rowing]),
            (["cycl", "bike", "spin"], [.cycling]),
            (["treadmill"], [.walking, .running]),
            (["run", "jog"], [.running]),
            (["walk", "hike"], [.walking]),
            (["swim"], [.swimming]),
        ]
        return words.first { $0.0.contains(where: n.contains) }?.1 ?? []
    }
}

public extension Workout {
    var watchIds: Set<UUID> { Set(exercises.compactMap { $0.watch?.id }) }

    /// Puts a Watch workout on the first cardio exercise it fits that has none yet, and fills its first set
    /// with what the Watch measured, keeping anything typed. False when nothing fits.
    mutating func link(_ w: WatchLink, as activity: WatchActivity, exercises byId: [UUID: Exercise]) -> Bool {
        guard !watchIds.contains(w.id) else { return false }
        for i in exercises.indices where exercises[i].watch == nil {
            guard let ex = byId[exercises[i].exerciseId], ex.watchActivities.contains(activity) else { continue }
            exercises[i].watch = w
            if exercises[i].sets.isEmpty { exercises[i].sets.append(WorkSet()) }
            var s = exercises[i].sets[0]
            if s.seconds == nil { s.seconds = w.seconds }
            if ex.type.hasDistance, s.meters == nil { s.meters = w.meters }
            if !s.done {
                s.done = true
                s.doneAt = w.end
            }
            exercises[i].sets[0] = s
            return true
        }
        return false
    }
}
