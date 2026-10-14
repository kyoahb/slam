import Foundation

/// A small starter library so a new install can log straight away. The Hevy import brings the rest.
public enum Catalog {
    public static func starter() -> [Exercise] {
        let list: [(String, ExerciseType, Equipment, Muscle)] = [
            ("Bench Press (Barbell)", .weightReps, .barbell, .chest),
            ("Incline Bench Press (Dumbbell)", .weightReps, .dumbbell, .chest),
            ("Chest Press (Machine)", .weightReps, .machine, .chest),
            ("Chest Fly (Machine)", .weightReps, .machine, .chest),
            ("Cable Fly Crossovers", .weightReps, .cable, .chest),
            ("Push Up", .repsOnly, .none, .chest),
            ("Dip", .bodyweightReps, .none, .triceps),
            ("Overhead Press (Barbell)", .weightReps, .barbell, .shoulders),
            ("Shoulder Press (Machine)", .weightReps, .machine, .shoulders),
            ("Lateral Raise (Dumbbell)", .weightReps, .dumbbell, .shoulders),
            ("Lateral Raise (Cable)", .weightReps, .cable, .shoulders),
            ("Rear Delt Fly (Machine)", .weightReps, .machine, .shoulders),
            ("Lat Pulldown (Cable)", .weightReps, .cable, .lats),
            ("Pull Up", .repsOnly, .none, .lats),
            ("Assisted Pull Up", .assistedBodyweight, .machine, .lats),
            ("Seated Cable Row", .weightReps, .cable, .upperBack),
            ("Bent Over Row (Barbell)", .weightReps, .barbell, .upperBack),
            ("T Bar Row", .weightReps, .machine, .upperBack),
            ("Shrug (Dumbbell)", .weightReps, .dumbbell, .traps),
            ("Back Extension", .weightReps, .machine, .lowerBack),
            ("Deadlift (Barbell)", .weightReps, .barbell, .lowerBack),
            ("Romanian Deadlift (Barbell)", .weightReps, .barbell, .hamstrings),
            ("Squat (Barbell)", .weightReps, .barbell, .quadriceps),
            ("Leg Press (Machine)", .weightReps, .machine, .quadriceps),
            ("Hack Squat (Machine)", .weightReps, .machine, .quadriceps),
            ("Leg Extension (Machine)", .weightReps, .machine, .quadriceps),
            ("Lying Leg Curl (Machine)", .weightReps, .machine, .hamstrings),
            ("Seated Leg Curl (Machine)", .weightReps, .machine, .hamstrings),
            ("Hip Thrust (Barbell)", .weightReps, .barbell, .glutes),
            ("Hip Abduction (Machine)", .weightReps, .machine, .abductors),
            ("Hip Adduction (Machine)", .weightReps, .machine, .adductors),
            ("Bulgarian Split Squat", .weightReps, .dumbbell, .quadriceps),
            ("Standing Calf Raise (Machine)", .weightReps, .machine, .calves),
            ("Bicep Curl (Dumbbell)", .weightReps, .dumbbell, .biceps),
            ("Preacher Curl (Machine)", .weightReps, .machine, .biceps),
            ("Hammer Curl (Dumbbell)", .weightReps, .dumbbell, .biceps),
            ("Triceps Pushdown", .weightReps, .cable, .triceps),
            ("Overhead Triceps Extension (Cable)", .weightReps, .cable, .triceps),
            ("Wrist Curl (Dumbbell)", .weightReps, .dumbbell, .forearms),
            ("Cable Crunch", .weightReps, .cable, .abdominals),
            ("Hanging Leg Raise", .repsOnly, .none, .abdominals),
            ("Plank", .duration, .none, .abdominals),
            ("Elliptical Trainer", .distanceDuration, .cardio, .cardio),
            ("Treadmill", .distanceDuration, .cardio, .cardio),
            ("Stair Machine", .duration, .cardio, .cardio),
            ("Rowing Machine", .distanceDuration, .cardio, .cardio),
            ("Cycling", .distanceDuration, .cardio, .cardio),
        ]
        return list.map { name, type, equipment, muscle in
            var e = Exercise(name: name, type: type, equipment: equipment, primary: muscle)
            if equipment == .cardio {
                e.settings = [Configurable(name: "Incline", perWorkout: true), Configurable(name: "Level", perWorkout: true)]
            }
            return e
        }
    }
}
