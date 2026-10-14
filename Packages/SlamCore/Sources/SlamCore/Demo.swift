import Foundation

/// Made-up history for screenshots and tests. Never loaded unless asked for.
public enum Demo {
    struct RNG {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func int(_ r: ClosedRange<Int>) -> Int { r.lowerBound + Int(next() % UInt64(r.count)) }
        mutating func chance(_ p: Double) -> Bool { Double(next() % 1000) / 1000 < p }
    }

    public static func library(now: Date = Date()) -> Library {
        var rng = RNG(state: 7)
        let anytime = Gym(name: "Anytime Fitness Barking")
        let gymGroup = Gym(name: "The Gym Group")

        let seat = Configurable(name: "Seat"), large = Configurable(name: "Large hinge"), small = Configurable(name: "Small hinge")
        let pad = Configurable(name: "Pad"), lever = Configurable(name: "Lever")
        let incline = Configurable(name: "Incline", perWorkout: true), level = Configurable(name: "Level", perWorkout: true)

        let legExt = Exercise(name: "Precor Leg Extension", primary: .quadriceps, unilateral: true, load: .pinMachine,
                              brand: "Precor", settings: [seat, large, small])
        let legCurl = Exercise(name: "Precor Prone Leg Curl Bilateral", primary: .hamstrings, load: .pinMachine,
                               brand: "Precor", settings: [pad, lever])
        let calf = Exercise(name: "Precor Leg Press - Calf Extension", primary: .calves, load: .pinMachine, brand: "Precor")
        let crunch = Exercise(name: "Cable Crunch", equipment: .cable, primary: .abdominals)
        let row = Exercise(name: "Precor T Bar Row - Row", primary: .upperBack, load: .plateLoaded, brand: "Precor")
        let shrug = Exercise(name: "Precor T Bar Row - Kelso Shrug", primary: .traps, load: .plateLoaded, brand: "Precor")
        let chest = Exercise(name: "Matrix Chest Press", primary: .chest, load: .pinMachine, brand: "Matrix")
        let lateral = Exercise(name: "Lateral Raise (Dumbbell)", equipment: .dumbbell, primary: .shoulders, unilateral: true)
        let elliptical = Exercise(name: "Precor Elliptical", type: .distanceDuration, equipment: .cardio, primary: .cardio,
                                  brand: "Precor", settings: [incline, level])
        let exercises = [legExt, legCurl, calf, crunch, row, shrug, chest, lateral, elliptical]
        let byId = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })

        func entry(_ e: Exercise, _ kinds: [SetKind], note: String = "", _ settings: [(Configurable, String)] = []) -> WorkoutExercise {
            var x = WorkoutExercise(exerciseId: e.id, note: note, sets: kinds.map { WorkSet(kind: $0) })
            for (c, v) in settings { x[setting: c.id] = v }
            return x
        }
        let folder = Folder(name: "fb")
        let a = Routine(name: "FB A", folderId: folder.id, exercises: [
            entry(legExt, [.warmup, .normal, .normal, .drop], note: "seatbelt under legs", [(seat, "3"), (large, "1"), (small, "3")]),
            entry(legCurl, [.warmup, .normal, .normal], note: "hips down, slow on the way back", [(pad, "4"), (lever, "2")]),
            entry(calf, [.normal, .normal, .normal]),
            entry(row, [.warmup, .normal, .normal]),
            entry(crunch, [.normal, .normal, .normal]),
        ])
        let b = Routine(name: "FB B", folderId: folder.id, exercises: [
            entry(chest, [.warmup, .normal, .normal, .normal], note: "handles at 2"),
            entry(shrug, [.normal, .normal, .normal]),
            entry(lateral, [.normal, .normal, .normal]),
            entry(elliptical, [.normal]),
        ])
        let c = Routine(name: "FB C", folderId: folder.id, exercises: [
            entry(legExt, [.warmup, .normal, .normal], note: "seatbelt under legs", [(seat, "3"), (large, "1"), (small, "3")]),
            entry(row, [.warmup, .normal, .normal]),
            entry(lateral, [.normal, .normal, .normal]),
        ])
        let d = Routine(name: "FB D", folderId: folder.id, exercises: [
            entry(chest, [.warmup, .normal, .normal]),
            entry(legCurl, [.warmup, .normal, .normal], note: "hips down, slow on the way back", [(pad, "4"), (lever, "2")]),
            entry(calf, [.normal, .normal, .normal]),
            entry(crunch, [.normal, .normal]),
        ])
        let routines = [a, b, c, d]

        func pinLoad(_ target: Double) -> Load {
            let stack = [74.0, 81, 88, 95, 102, 109].last(where: { $0 <= target }) ?? 74
            var rest = target - stack
            let addOn: Double = rest >= 2 ? 2 : 0
            rest -= addOn
            let pin = Plates.closest(rest, from: [1.25, 2.5, 5])
            return Load(base: stack, addOn: addOn, plates: pin)
        }

        func sets(_ e: Exercise, _ kinds: [SetKind], progress p: Double) -> [WorkSet] {
            var out: [WorkSet] = []
            for (i, kind) in kinds.enumerated() {
                var s = WorkSet(kind: kind, done: true)
                let reps = kind == .warmup ? 10 : kind == .drop ? rng.int(6...9) : rng.int(7...11) - i / 2
                let rir: Int? = kind == .warmup ? nil : rng.chance(0.8) ? rng.int(0...2) : nil
                switch e.load {
                case .pinMachine:
                    let top = (e.id == legExt.id ? 90 + 28.5 * p : e.id == chest.id ? 60 + 22 * p : 74 + 30 * p)
                    let target = kind == .warmup ? top * 0.55 : kind == .drop ? top * 0.7 : top - Double(rng.int(0...1)) * 2.5
                    let load = pinLoad(target)
                    s.load = load
                    s.kg = load.total(.pinMachine)
                case .plateLoaded:
                    let top = (e.id == row.id ? 40 + 20 * p : 60 + 30 * p)
                    let perSide = Plates.closest((kind == .warmup ? top * 0.5 : top) / 2, from: Plates.standard)
                    s.load = Load(plates: perSide)
                    s.kg = s.load?.total(.plateLoaded)
                case .plain:
                    if e.type.hasKg {
                        let top = e.id == lateral.id ? 10 + 4 * p : 30 + 15 * p
                        s.kg = ((top) / 1.25).rounded() * 1.25
                    }
                }
                if e.type.hasReps {
                    s.reps = reps
                    s.rir = rir
                    if e.unilateral {
                        s.repsR = max(1, reps - rng.int(0...1))
                        s.rirR = rir.map { max(0, $0 - rng.int(0...1)) }
                    }
                } else {
                    s.seconds = 1200 + rng.int(0...10) * 60
                    s.meters = Double(2500 + rng.int(0...15) * 100)
                }
                out.append(s)
            }
            return out
        }

        var cal = Stats.mondayCalendar()
        cal.timeZone = TimeZone(identifier: "Europe/London") ?? .current
        let weeks = 14
        var workouts: [Workout] = []
        let plan = [a, b, c, a, b, d]
        let shortNotes = ["", "", "", "felt strong", "", "left knee a bit sore", "", "", "slept badly", ""]
        var n = 0
        let thisWeek = Stats.weekStart(now, cal)
        for week in stride(from: weeks, through: 1, by: -1) {
            guard let monday = cal.date(byAdding: .weekOfYear, value: -week, to: thisWeek) else { continue }
            for day in [0, 2, 4] where !(week == 6 && day == 2) {
                guard let date = cal.date(byAdding: .day, value: day, to: monday),
                      let start = cal.date(bySettingHour: 18, minute: rng.int(0...40), second: 0, of: date) else { continue }
                let routine = plan[n % plan.count]
                let p = Double(workouts.count) / Double(weeks * 3)
                var w = Workout(title: routine.name, start: start, end: start.addingTimeInterval(Double(rng.int(48...75) * 60)),
                                gymId: n % 7 == 5 ? gymGroup.id : anytime.id, routineId: routine.id)
                w.exercises = routine.exercises.map { r in
                    let ex = byId[r.exerciseId]!
                    var e = WorkoutExercise(exerciseId: ex.id, settings: r.settings,
                                            sets: sets(ex, r.sets.map(\.kind), progress: p))
                    e.note = shortNotes[rng.int(0...shortNotes.count - 1)]
                    if ex.id == legExt.id, let l = e.sets.first(where: { $0.kind == .normal })?.load {
                        e.note = "\(Format.kg(l.base)) + \(Format.kg(l.addOn)) + (\(l.plates.map(Format.kg).joined(separator: " ")))gp"
                    }
                    if ex.id == elliptical.id {
                        e[setting: incline.id] = String(rng.int(4...8))
                        e[setting: level.id] = String(rng.int(8...12))
                    }
                    return e
                }
                if n % 9 == 4 { w.notes = "Good session, gym was quiet." }
                workouts.append(w)
                n += 1
            }
        }
        workouts.sort { $0.start > $1.start }

        var active = Workout.from(a, exercises: byId, history: workouts, gymId: anytime.id,
                                  now: now.addingTimeInterval(-32 * 60 - 14))
        if let last = Previous.last(legExt.id, in: workouts) {
            let prev = Previous.match(active.exercises[0].sets, last: last.sets)
            active.exercises[0].sets[0] = active.exercises[0].sets[0].filled(from: prev[0])
            active.exercises[0].sets[0].done = true
            var s1 = active.exercises[0].sets[1]
            s1.load = Load(base: 109, addOn: 2, plates: [5, 2.5])
            s1.kg = 118.5
            s1.reps = 8; s1.rir = 1; s1.repsR = 7; s1.rirR = 0
            s1.done = true
            active.exercises[0].sets[1] = s1
            active.exercises[0].note = ""
        }

        return Library(exercises: exercises + Catalog.starter(), folders: [folder], routines: routines,
                       gyms: [anytime, gymGroup], settings: Settings(gymId: anytime.id), workouts: workouts,
                       active: active)
    }
}
