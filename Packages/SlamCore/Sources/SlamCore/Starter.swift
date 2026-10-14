import Foundation

public extension Library {
    /// 0.1.0 (1) and (2) put 47 starter exercises on every new install. Takes out the ones never used or changed,
    /// once, and says how many went. Delete this with the next change to the stored format.
    mutating func removeUnusedStarter() -> Int {
        let used = Set(workouts.flatMap { $0.exercises.map(\.exerciseId) }
            + routines.flatMap { $0.exercises.map(\.exerciseId) }
            + (active?.exercises.map(\.exerciseId) ?? []))
        let before = exercises.count
        exercises.removeAll { e in
            Self.starterNames.contains(e.name) && !used.contains(e.id) && e.stack.isEmpty && e.addOn == nil
                && e.plateSides == 0 && e.bar == nil
                && e.brand.isEmpty && e.photo == nil && e.hevyId == nil && e.secondary.isEmpty && !e.unilateral
                && e.settings.allSatisfy { ["Incline", "Level"].contains($0.name) }
        }
        return before - exercises.count
    }

    private static let starterNames: Set<String> = [
        "Bench Press (Barbell)", "Incline Bench Press (Dumbbell)", "Chest Press (Machine)", "Chest Fly (Machine)",
        "Cable Fly Crossovers", "Push Up", "Dip", "Overhead Press (Barbell)", "Shoulder Press (Machine)",
        "Lateral Raise (Dumbbell)", "Lateral Raise (Cable)", "Rear Delt Fly (Machine)", "Lat Pulldown (Cable)",
        "Pull Up", "Assisted Pull Up", "Seated Cable Row", "Bent Over Row (Barbell)", "T Bar Row",
        "Shrug (Dumbbell)", "Back Extension", "Deadlift (Barbell)", "Romanian Deadlift (Barbell)", "Squat (Barbell)",
        "Leg Press (Machine)", "Hack Squat (Machine)", "Leg Extension (Machine)", "Lying Leg Curl (Machine)",
        "Seated Leg Curl (Machine)", "Hip Thrust (Barbell)", "Hip Abduction (Machine)", "Hip Adduction (Machine)",
        "Bulgarian Split Squat", "Standing Calf Raise (Machine)", "Bicep Curl (Dumbbell)", "Preacher Curl (Machine)",
        "Hammer Curl (Dumbbell)", "Triceps Pushdown", "Overhead Triceps Extension (Cable)", "Wrist Curl (Dumbbell)",
        "Cable Crunch", "Hanging Leg Raise", "Plank", "Elliptical Trainer", "Treadmill", "Stair Machine",
        "Rowing Machine", "Cycling"
    ]
}
