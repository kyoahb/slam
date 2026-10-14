import Foundation

/// A small starter library so a new install can log straight away. The Hevy import brings the rest.
public enum Catalog {
    public static func starter() -> [Exercise] {
        let list: [(String, ExerciseType, Equipment, Muscle, LoadKind)] = [
            ("Bench Press (Barbell)", .weightReps, .barbell, .chest, .plateLoaded),
            ("Incline Bench Press (Dumbbell)", .weightReps, .dumbbell, .chest, .plain),
            ("Chest Press (Machine)", .weightReps, .machine, .chest, .pinMachine),
            ("Chest Fly (Machine)", .weightReps, .machine, .chest, .pinMachine),
            ("Cable Fly Crossovers", .weightReps, .cable, .chest, .plain),
            ("Push Up", .repsOnly, .none, .chest, .plain),
            ("Dip", .bodyweightReps, .none, .triceps, .plain),
            ("Overhead Press (Barbell)", .weightReps, .barbell, .shoulders, .plateLoaded),
            ("Shoulder Press (Machine)", .weightReps, .machine, .shoulders, .pinMachine),
            ("Lateral Raise (Dumbbell)", .weightReps, .dumbbell, .shoulders, .plain),
            ("Lateral Raise (Cable)", .weightReps, .cable, .shoulders, .plain),
            ("Rear Delt Fly (Machine)", .weightReps, .machine, .shoulders, .pinMachine),
            ("Lat Pulldown (Cable)", .weightReps, .cable, .lats, .pinMachine),
            ("Pull Up", .repsOnly, .none, .lats, .plain),
            ("Assisted Pull Up", .assistedBodyweight, .machine, .lats, .pinMachine),
            ("Seated Cable Row", .weightReps, .cable, .upperBack, .pinMachine),
            ("Bent Over Row (Barbell)", .weightReps, .barbell, .upperBack, .plateLoaded),
            ("T Bar Row", .weightReps, .machine, .upperBack, .plateLoaded),
            ("Shrug (Dumbbell)", .weightReps, .dumbbell, .traps, .plain),
            ("Back Extension", .weightReps, .machine, .lowerBack, .plain),
            ("Deadlift (Barbell)", .weightReps, .barbell, .lowerBack, .plateLoaded),
            ("Romanian Deadlift (Barbell)", .weightReps, .barbell, .hamstrings, .plateLoaded),
            ("Squat (Barbell)", .weightReps, .barbell, .quadriceps, .plateLoaded),
            ("Leg Press (Machine)", .weightReps, .machine, .quadriceps, .plateLoaded),
            ("Hack Squat (Machine)", .weightReps, .machine, .quadriceps, .plateLoaded),
            ("Leg Extension (Machine)", .weightReps, .machine, .quadriceps, .pinMachine),
            ("Lying Leg Curl (Machine)", .weightReps, .machine, .hamstrings, .pinMachine),
            ("Seated Leg Curl (Machine)", .weightReps, .machine, .hamstrings, .pinMachine),
            ("Hip Thrust (Barbell)", .weightReps, .barbell, .glutes, .plateLoaded),
            ("Hip Abduction (Machine)", .weightReps, .machine, .abductors, .pinMachine),
            ("Hip Adduction (Machine)", .weightReps, .machine, .adductors, .pinMachine),
            ("Bulgarian Split Squat", .weightReps, .dumbbell, .quadriceps, .plain),
            ("Standing Calf Raise (Machine)", .weightReps, .machine, .calves, .pinMachine),
            ("Bicep Curl (Dumbbell)", .weightReps, .dumbbell, .biceps, .plain),
            ("Preacher Curl (Machine)", .weightReps, .machine, .biceps, .pinMachine),
            ("Hammer Curl (Dumbbell)", .weightReps, .dumbbell, .biceps, .plain),
            ("Triceps Pushdown", .weightReps, .cable, .triceps, .plain),
            ("Overhead Triceps Extension (Cable)", .weightReps, .cable, .triceps, .plain),
            ("Wrist Curl (Dumbbell)", .weightReps, .dumbbell, .forearms, .plain),
            ("Cable Crunch", .weightReps, .cable, .abdominals, .plain),
            ("Hanging Leg Raise", .repsOnly, .none, .abdominals, .plain),
            ("Plank", .duration, .none, .abdominals, .plain),
            ("Elliptical Trainer", .distanceDuration, .cardio, .cardio, .plain),
            ("Treadmill", .distanceDuration, .cardio, .cardio, .plain),
            ("Stair Machine", .duration, .cardio, .cardio, .plain),
            ("Rowing Machine", .distanceDuration, .cardio, .cardio, .plain),
            ("Cycling", .distanceDuration, .cardio, .cardio, .plain),
        ]
        return list.map { name, type, equipment, muscle, load in
            var e = Exercise(name: name, type: type, equipment: equipment, primary: muscle, load: load)
            if equipment == .cardio {
                e.settings = [Configurable(name: "Incline", perWorkout: true), Configurable(name: "Level", perWorkout: true)]
            }
            return e
        }
    }
}
