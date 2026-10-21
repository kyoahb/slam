import Foundation
import Hummingbird
import SlamCore

/// What models see and may change, through the MCP tools. Reads take the read or write token; changes take the
/// write token, and changing or deleting a logged workout also needs `confirm=true`.
enum Agent {
    static func routes(_ router: Router<BasicRequestContext>, _ vault: Vault, _ tokens: Tokens) {
        let reads: [Role] = [.read, .write]
        router.get("v1/agent/workouts") { request, _ -> Response in
            try Routes.check(request, tokens, reads)
            let q = request.uri.queryParameters
            let view = await View(vault.library())
            let from = q["start"].flatMap { Self.date(String($0)) } ?? .distantPast
            let to = q["end"].flatMap { Self.date(String($0), endOfDay: true) } ?? .distantFuture
            let limit = Int(q["limit"].map(String.init) ?? "") ?? 20
            let list = view.lib.workouts.filter { $0.start >= from && $0.start <= to }.prefix(max(1, min(limit, 500)))
            return try out(list.map(view.summary))
        }
        router.get("v1/agent/workouts/:id") { request, context -> Response in
            try Routes.check(request, tokens, reads)
            let view = await View(vault.library())
            return try out(view.detail(try view.workout(context.parameters.require("id"))))
        }
        router.get("v1/agent/active") { request, _ -> Response in
            try Routes.check(request, tokens, reads)
            let view = await View(vault.library())
            return try out(view.lib.active.map(view.detail))
        }
        router.get("v1/agent/exercises") { request, _ -> Response in
            try Routes.check(request, tokens, reads)
            let q = request.uri.queryParameters
            let view = await View(vault.library())
            let text = q["query"].map { String($0).lowercased() } ?? ""
            let muscle = q["muscle"].map { String($0).lowercased() } ?? ""
            let equipment = q["equipment"].map { String($0).lowercased() } ?? ""
            let list = view.exercises.filter { e in
                (text.isEmpty || (e.name + " " + e.brand).lowercased().contains(text))
                    && (muscle.isEmpty || ([e.primary] + e.secondary).contains { $0.rawValue.lowercased() == muscle || $0.title.lowercased() == muscle })
                    && (equipment.isEmpty || e.equipment.rawValue == equipment)
            }
            return try out(list.sorted { $0.name < $1.name }.map(view.exercise))
        }
        router.get("v1/agent/history") { request, _ -> Response in
            try Routes.check(request, tokens, reads)
            let q = request.uri.queryParameters
            let view = await View(vault.library())
            let ex = try view.find(q["exercise"].map(String.init) ?? "")
            let limit = Int(q["limit"].map(String.init) ?? "") ?? 10
            return try out(view.history(ex, limit: max(1, min(limit, 200))))
        }
        router.get("v1/agent/progress") { request, _ -> Response in
            try Routes.check(request, tokens, reads)
            let q = request.uri.queryParameters
            let view = await View(vault.library())
            let ex = try view.find(q["exercise"].map(String.init) ?? "")
            let metric = try q["metric"].map { name in
                guard let m = Metric(rawValue: String(name)) else {
                    throw HTTPError(.badRequest, message: "metric is one of " + Metric.allCases.map(\.rawValue).joined(separator: ", "))
                }
                return m
            } ?? Metric.available(for: ex.type).first ?? .reps
            return try out(view.progress(ex, metric, weekly: q["by"] == "week"))
        }
        router.get("v1/agent/records") { request, _ -> Response in
            try Routes.check(request, tokens, reads)
            let q = request.uri.queryParameters
            let view = await View(vault.library())
            if let name = q["exercise"], !name.isEmpty {
                return try out([view.bests(try view.find(String(name)))])
            }
            return try out(view.exercises.map(view.bests).filter { $0.sessions > 0 }.sorted { $0.exercise < $1.exercise })
        }
        router.get("v1/agent/weeks") { request, _ -> Response in
            try Routes.check(request, tokens, reads)
            let weeks = Int(request.uri.queryParameters["weeks"].map(String.init) ?? "") ?? 8
            let view = await View(vault.library())
            return try out(view.weeks(max(1, min(weeks, 260))))
        }
        router.get("v1/agent/routines") { request, _ -> Response in
            try Routes.check(request, tokens, reads)
            let view = await View(vault.library())
            return try out(view.routines())
        }

        router.post("v1/agent/routines") { request, _ -> Response in
            try Routes.check(request, tokens, [.write])
            let body = try await read(request, RoutineIn.self, limit: 1 << 20)
            let view = await View(vault.library())
            let (routine, folder) = try view.routine(body)
            if let folder { try await vault.put(record(folder)) }
            try await vault.put(record(routine))
            return try out(await View(vault.library()).routines().routines.first { $0.id == routine.id })
        }
        router.post("v1/agent/exercises") { request, _ -> Response in
            try Routes.check(request, tokens, [.write])
            let body = try await read(request, ExerciseIn.self, limit: 1 << 20)
            let view = await View(vault.library())
            let ex = try view.exercise(body)
            var lib = view.lib
            let touched = lib.save(ex)
            for r in records(lib, saving: ex.id, touched) { try await vault.put(r) }
            return try out(await View(vault.library()).exercise(ex))
        }
        router.post("v1/agent/workouts") { request, _ -> Response in
            try Routes.check(request, tokens, [.write])
            let body = try await read(request, WorkoutIn.self, limit: 4 << 20)
            let view = await View(vault.library())
            let w = try view.newWorkout(body)
            try await vault.put(record(w))
            return try out(await View(vault.library()).detail(w))
        }
        router.post("v1/agent/workouts/:id") { request, context -> Response in
            try Routes.check(request, tokens, [.write])
            let body = try await read(request, WorkoutChange.self, limit: 4 << 20)
            let view = await View(vault.library())
            let current = try view.workout(context.parameters.require("id"))
            guard body.confirm == true else {
                throw HTTPError(.conflict, message: "Changing or deleting a logged workout needs confirm=true. Check it with slam_get_workout first.")
            }
            if body.delete == true {
                try await vault.put(record(current).tombstone())
                return try out(["deleted": current.id.uuidString])
            }
            let w = try view.change(current, body)
            try await vault.put(record(w))
            return try out(await View(vault.library()).detail(w))
        }
    }

    // MARK: Records

    static func record(_ e: Exercise) -> SyncRecord { var r = SyncRecord(kind: .exercise, id: e.id.uuidString); r.exercise = e; return r }
    static func record(_ f: Folder) -> SyncRecord { var r = SyncRecord(kind: .folder, id: f.id.uuidString); r.folder = f; return r }
    static func record(_ x: Routine) -> SyncRecord { var r = SyncRecord(kind: .routine, id: x.id.uuidString); r.routine = x; return r }
    static func record(_ w: Workout) -> SyncRecord { var r = SyncRecord(kind: .workout, id: w.id.uuidString); r.workout = w; return r }
    static func record(_ m: Machine) -> SyncRecord { var r = SyncRecord(kind: .machine, id: m.id.uuidString); r.machine = m; return r }

    /// An exercise as `Library.save` stored it, and what that changed with it. Unchanged ones are not written.
    static func records(_ lib: Library, saving id: UUID, _ t: Touched) -> [SyncRecord] {
        var out = lib.exercises.filter { $0.id == id }.map(record)
        out += lib.machines.filter { $0.id == t.machine }.map(record)
        if t.routines { out += lib.routines.map(record) }
        out += lib.workouts.filter { t.workouts.contains($0.id) }.map(record)
        return out
    }

    // MARK: Output

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(Agent.local.string(from: date))
        }
        e.keyEncodingStrategy = .convertToSnakeCase
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            guard let date = Agent.date(s) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not a date: \(s)"))
            }
            return date
        }
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    /// Times as UK clock times with their offset: "2026-10-14T18:05:00+01:00".
    static let local: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "Europe/London")
        return f
    }()

    static func read<T: Decodable>(_ request: Request, _ type: T.Type, limit: Int) async throws -> T {
        let buffer = try await request.body.collect(upTo: limit)
        do {
            return try decoder.decode(type, from: Data(buffer.readableBytesView))
        } catch let DecodingError.dataCorrupted(c) {
            throw HTTPError(.badRequest, message: Self.path(c.codingPath) + c.debugDescription)
        } catch let DecodingError.keyNotFound(key, c) {
            throw HTTPError(.badRequest, message: Self.path(c.codingPath + [key]) + "missing")
        } catch let DecodingError.typeMismatch(_, c), let DecodingError.valueNotFound(_, c) {
            throw HTTPError(.badRequest, message: Self.path(c.codingPath) + c.debugDescription)
        } catch {
            throw HTTPError(.badRequest, message: "\(error)")
        }
    }

    private static func path(_ keys: [CodingKey]) -> String {
        keys.isEmpty ? "" : keys.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".") + ": "
    }

    static func out<T: Encodable>(_ value: T) throws -> Response {
        Response(status: .ok, headers: [.contentType: "application/json"],
                 body: ResponseBody(byteBuffer: ByteBuffer(bytes: try encoder.encode(value))))
    }

    /// "2026-10-14", "2026-10-14T18:05", "2026-10-14T18:05:00Z" or with an offset. Times without a zone are UK time.
    static func date(_ s: String, endOfDay: Bool = false) -> Date? {
        let s = s.trimmingCharacters(in: .whitespaces)
        if let d = ISO8601DateFormatter().date(from: s) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/London")
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm"] {
            f.dateFormat = format
            if let d = f.date(from: s) { return d }
        }
        f.dateFormat = "yyyy-MM-dd"
        guard let day = f.date(from: s) else { return nil }
        return endOfDay ? day.addingTimeInterval(86400 - 1) : day
    }
}

// MARK: Shapes models send

struct SetIn: Decodable {
    var kind: SetKind?
    var kg: Double?
    var reps: Int?
    var repsRight: Int?
    var rir: Int?
    var rirRight: Int?
    var seconds: Int?
    var meters: Double?
}

struct EntryIn: Decodable {
    /// An exercise id or its exact name.
    var exercise: String
    var note: String?
    /// Setting name → value: {"Seat": "5"}.
    var settings: [String: String]?
    var sets: [SetIn]?
}

struct RoutineIn: Decodable {
    var id: UUID?
    var name: String
    var folder: String?
    var exercises: [EntryIn]
}

struct SettingIn: Decodable {
    var name: String
    var perWorkout: Bool?
}

struct RangeIn: Decodable {
    var from: Double
    var step: Double
    var to: Double
}

struct ExerciseIn: Decodable {
    /// Which exercise to change; leave out (with a new name) to add one.
    var id: UUID?
    var name: String?
    var type: ExerciseType?
    var equipment: Equipment?
    var primary: Muscle?
    var secondary: [Muscle]?
    var unilateral: Bool?
    var brand: String?
    var stack: [Double]?
    var stackRange: RangeIn?
    /// 0 removes it.
    var addOn: Double?
    /// A stack machine's pin for plates.
    var pin: Bool?
    var bar: Double?
    var plateSides: Int?
    /// Replaces the list; values already logged stay with settings of the same name.
    var settings: [SettingIn]?
}

struct WorkoutIn: Decodable {
    var title: String
    var start: Date
    var end: Date?
    var minutes: Int?
    var gym: String?
    var routine: String?
    var notes: String?
    var exercises: [EntryIn]
    /// Needed when another workout already starts within two hours of this one.
    var confirm: Bool?
}

struct WorkoutChange: Decodable {
    var confirm: Bool?
    var delete: Bool?
    var title: String?
    var start: Date?
    var end: Date?
    var gym: String?
    var notes: String?
    /// Replaces every exercise and set.
    var exercises: [EntryIn]?
}

// MARK: Shapes models get

struct SetOut: Encodable {
    var set: String
    var text: String
    var kg: Double?
    var reps: Int?
    var repsRight: Int?
    var rir: Int?
    var rirRight: Int?
    var seconds: Int?
    var meters: Double?
    var done: Bool
    var records: [String]?
}

struct WatchOut: Encodable {
    var minutes: Double
    var km: Double?
    var kcal: Int?
    var heartRate: Int?
}

struct EntryOut: Encodable {
    var exerciseId: UUID
    var exercise: String
    var note: String?
    var settings: [String: String]?
    var watch: WatchOut?
    var sets: [SetOut]
}

struct WorkoutSummary: Encodable {
    var id: UUID
    var title: String
    var start: Date
    var minutes: Int
    var gym: String?
    var volumeKg: Double
    var sets: Int
    var records: Int
    var exercises: [String]
}

struct WorkoutOut: Encodable {
    var id: UUID
    var title: String
    var start: Date
    var end: Date?
    var minutes: Int
    var gym: String?
    var routine: String?
    var notes: String?
    var volumeKg: Double
    var records: Int
    var photos: Int
    var exercises: [EntryOut]
}

struct ExerciseOut: Encodable {
    var id: UUID
    var name: String
    var type: String
    var equipment: String
    var brand: String?
    /// The machine it shares its weights and setup with, and the other exercises done on it.
    var machine: String?
    var sameMachine: [String]?
    var primary: String
    var secondary: [String]
    var unilateral: Bool
    var stack: [Double]?
    var addOn: Double?
    var pin: Bool?
    var bar: Double?
    var plateSides: Int?
    var settings: [String]?
    var workouts: Int
    var last: Date?
}

struct SessionOut: Encodable {
    var workoutId: UUID
    var date: Date
    var gym: String?
    var settings: [String: String]?
    var note: String?
    var sets: [String]
    var e1rm: Double?
}

struct BestsOut: Encodable {
    var exercise: String
    var sessions: Int
    var heaviest: String?
    var e1rm: Double?
    var e1rmSet: String?
    var bestSetVolume: String?
    var bestSessionVolumeKg: Double?
    var mostReps: String?
    var longest: String?
    var farthest: String?
}

struct HistoryOut: Encodable {
    var exercise: ExerciseOut
    var bests: BestsOut
    var sessions: [SessionOut]
}

struct PointOut: Encodable {
    var date: Date
    var value: Double
    var workoutId: UUID?
}

struct ProgressOut: Encodable {
    var exercise: String
    var metric: String
    var by: String
    var points: [PointOut]
}

struct WeekOut: Encodable {
    var weekStart: Date
    var workouts: Int
    var minutes: Int
    var volumeKg: Double
    var sets: Int
    var reps: Int
    var setsPerMuscle: [String: Int]
}

struct RoutineOut: Encodable {
    var id: UUID
    var name: String
    var folder: String?
    var exercises: [EntryOut]
}

struct RoutinesOut: Encodable {
    var folders: [String]
    var routines: [RoutineOut]
}

// MARK: The library, read the way the phone reads it

struct View {
    let lib: Library
    /// With their machines' weights and setup.
    let exercises: [Exercise]
    let byId: [UUID: Exercise]
    let records: [UUID: [Record]]

    init(_ lib: Library) {
        self.lib = lib
        exercises = lib.resolved
        byId = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        records = Records.all(lib.workouts, exercises: byId)
    }

    func gym(_ id: UUID?) -> String? { id.flatMap { id in lib.gyms.first { $0.id == id }?.name } }

    func workout(_ id: String) throws -> Workout {
        guard let w = lib.workouts.first(where: { $0.id.uuidString.lowercased() == id.lowercased() }) else {
            throw HTTPError(.notFound, message: "No workout with id \(id). Find it with slam_recent_workouts.")
        }
        return w
    }

    /// By id, exact name (any case), or the one name containing it.
    func find(_ ref: String) throws -> Exercise {
        let ref = ref.trimmingCharacters(in: .whitespaces)
        guard !ref.isEmpty else { throw HTTPError(.badRequest, message: "Name an exercise.") }
        if let id = UUID(uuidString: ref), let e = byId[id] { return e }
        let low = ref.lowercased()
        if let e = exercises.first(where: { $0.name.lowercased() == low }) { return e }
        let near = exercises.filter { $0.name.lowercased().contains(low) }
        if near.count == 1 { return near[0] }
        let names = (near.isEmpty ? exercises.filter { e in
            low.split(separator: " ").contains { e.name.lowercased().contains($0) }
        } : near).map(\.name).sorted().prefix(15)
        throw HTTPError(.notFound, message: "No single exercise matches \"\(ref)\"."
            + (names.isEmpty ? " Use slam_find_exercises." : " Close: " + names.joined(separator: "; ")))
    }

    func summary(_ w: Workout) -> WorkoutSummary {
        WorkoutSummary(id: w.id, title: w.title, start: w.start, minutes: Int(w.duration / 60), gym: gym(w.gymId),
                       volumeKg: Stats.volume(w, byId).rounded(), sets: Stats.sets(w), records: records[w.id]?.count ?? 0,
                       exercises: w.exercises.map { byId[$0.exerciseId]?.name ?? "Deleted exercise" })
    }

    func detail(_ w: Workout) -> WorkoutOut {
        let found = records[w.id] ?? []
        return WorkoutOut(id: w.id, title: w.title, start: w.start, end: w.end, minutes: Int(w.duration / 60), gym: gym(w.gymId),
                          routine: w.routineId.flatMap { id in lib.routines.first { $0.id == id }?.name },
                          notes: w.notes.isEmpty ? nil : w.notes, volumeKg: Stats.volume(w, byId).rounded(),
                          records: found.count, photos: w.photos.count,
                          exercises: w.exercises.map { entry($0, records: found) })
    }

    func entry(_ e: WorkoutExercise, records found: [Record] = []) -> EntryOut {
        let ex = byId[e.exerciseId] ?? Exercise(id: e.exerciseId, name: "Deleted exercise")
        let labels = Previous.labels(e.sets)
        let sets = e.sets.enumerated().map { i, s in
            let won = found.filter { $0.setId == s.id }.map(\.kind.title)
            return SetOut(set: labels[i], text: SetText.describe(s, ex, split: true) + SetText.rir(s, ex), kg: s.kg,
                          reps: s.reps, repsRight: s.repsR, rir: s.rir, rirRight: s.rirR, seconds: s.seconds,
                          meters: s.meters, done: s.done, records: won.isEmpty ? nil : won)
        }
        let watch = e.watch.map {
            WatchOut(minutes: (Double($0.seconds) / 6).rounded() / 10, km: $0.meters.map { ($0 / 10).rounded() / 100 },
                     kcal: $0.kcal.map { Int($0.rounded()) }, heartRate: $0.heartRate.map { Int($0.rounded()) })
        }
        let settings = settingsByName(e, ex)
        return EntryOut(exerciseId: ex.id, exercise: ex.name, note: e.note.isEmpty ? nil : e.note,
                        settings: settings.isEmpty ? nil : settings, watch: watch, sets: sets)
    }

    func settingsByName(_ e: WorkoutExercise, _ ex: Exercise) -> [String: String] {
        var out: [String: String] = [:]
        for c in ex.settings where !e[setting: c.id].isEmpty { out[c.name] = e[setting: c.id] }
        return out
    }

    func exercise(_ e: Exercise) -> ExerciseOut {
        let used = lib.workouts.filter { $0.exercises.contains { $0.exerciseId == e.id } }
        let same = e.machineId == nil ? [] : exercises.filter { $0.machineId == e.machineId && $0.id != e.id }.map(\.name).sorted()
        return ExerciseOut(id: e.id, name: e.name, type: e.type.rawValue, equipment: e.equipment.rawValue,
                           brand: e.brand.isEmpty ? nil : e.brand, machine: lib.machine(e.machineId)?.name,
                           sameMachine: same.isEmpty ? nil : same, primary: e.primary.rawValue,
                           secondary: e.secondary.map(\.rawValue), unilateral: e.unilateral,
                           stack: e.stack.isEmpty ? nil : e.stack, addOn: e.addOn, pin: e.pin ? true : nil, bar: e.bar,
                           plateSides: e.plateSides == 0 ? nil : e.plateSides,
                           settings: e.settings.isEmpty ? nil : e.settings.map { $0.name + ($0.perWorkout ? " (each workout)" : "") },
                           workouts: used.count, last: used.map(\.start).max())
    }

    func history(_ ex: Exercise, limit: Int) -> HistoryOut {
        var sessions: [SessionOut] = []
        for w in lib.workouts {
            for e in w.exercises where e.exerciseId == ex.id {
                let settings = settingsByName(e, ex)
                let best = SetMath.working(e).compactMap(SetMath.e1rm).max()
                sessions.append(SessionOut(workoutId: w.id, date: w.start, gym: gym(w.gymId),
                                           settings: settings.isEmpty ? nil : settings, note: e.note.isEmpty ? nil : e.note,
                                           sets: entry(e).sets.map { $0.set + ": " + $0.text },
                                           e1rm: best.map { ($0 * 10).rounded() / 10 }))
            }
            if sessions.count >= limit { break }
        }
        return HistoryOut(exercise: exercise(ex), bests: bests(ex), sessions: sessions)
    }

    func bests(_ ex: Exercise) -> BestsOut {
        let b = Records.bests(ex.id, type: ex.type, in: lib.workouts)
        let text = { (s: WorkSet?) in s.map { SetText.describe($0, ex) } }
        return BestsOut(exercise: ex.name, sessions: b.sessions, heaviest: text(b.heaviest),
                        e1rm: b.e1rm.flatMap(SetMath.e1rm).map { ($0 * 10).rounded() / 10 }, e1rmSet: text(b.e1rm),
                        bestSetVolume: text(b.setVolume), bestSessionVolumeKg: b.sessionVolume > 0 ? b.sessionVolume.rounded() : nil,
                        mostReps: ex.type.hasReps ? text(b.reps) : nil, longest: ex.type.hasTime ? text(b.seconds) : nil,
                        farthest: ex.type.hasDistance ? text(b.meters) : nil)
    }

    func progress(_ ex: Exercise, _ metric: Metric, weekly: Bool) -> ProgressOut {
        let points = Stats.series(ex.id, lib.workouts, metric: metric, type: ex.type)
        var out = points.map { PointOut(date: $0.date, value: ($0.value * 10).rounded() / 10, workoutId: $0.workoutId) }
        if weekly {
            let cal = Stats.mondayCalendar()
            let summed: Set<Metric> = [.session, .reps, .seconds, .meters]
            var byWeek: [Date: Double] = [:]
            for p in points {
                let week = Stats.weekStart(p.date, cal)
                byWeek[week] = summed.contains(metric) ? (byWeek[week] ?? 0) + p.value : max(byWeek[week] ?? 0, p.value)
            }
            out = byWeek.keys.sorted().map { PointOut(date: $0, value: ((byWeek[$0] ?? 0) * 10).rounded() / 10, workoutId: nil) }
        }
        return ProgressOut(exercise: ex.name, metric: metric.rawValue, by: weekly ? "week" : "workout", points: out)
    }

    func weeks(_ n: Int) -> [WeekOut] {
        let cal = Stats.mondayCalendar()
        return Stats.weeks(lib.workouts, byId, calendar: cal).suffix(n).reversed().map { week in
            let end = cal.date(byAdding: .weekOfYear, value: 1, to: week.start) ?? week.start
            let muscles = Stats.setsPerMuscle(lib.workouts, byId, from: week.start, to: end)
            return WeekOut(weekStart: week.start, workouts: week.workouts, minutes: Int(week.seconds / 60),
                           volumeKg: week.volume.rounded(), sets: week.sets, reps: week.reps,
                           setsPerMuscle: Dictionary(muscles.map { ($0.muscle.rawValue, $0.sets) }, uniquingKeysWith: +))
        }
    }

    func routines() -> RoutinesOut {
        let folders = Dictionary(lib.folders.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        return RoutinesOut(folders: lib.folders.map(\.name), routines: lib.routines.map { r in
            RoutineOut(id: r.id, name: r.name, folder: r.folderId.flatMap { folders[$0] }, exercises: r.exercises.map { entry($0) })
        })
    }

    // MARK: Changes

    /// A routine from what a model sent, and the new folder it named if there was none by that name.
    func routine(_ body: RoutineIn) throws -> (Routine, Folder?) {
        let name = body.name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { throw HTTPError(.badRequest, message: "A routine needs a name.") }
        var r = body.id.flatMap { id in lib.routines.first { $0.id == id } } ?? Routine(id: body.id ?? UUID(), name: name)
        r.name = name
        var folder: Folder?
        if let f = body.folder?.trimmingCharacters(in: .whitespaces), !f.isEmpty {
            if let have = lib.folders.first(where: { $0.name.lowercased() == f.lowercased() }) {
                r.folderId = have.id
            } else {
                folder = Folder(name: f)
                r.folderId = folder?.id
            }
        }
        r.exercises = try body.exercises.map { try entry($0, done: false) }
        return (r, folder)
    }

    func entry(_ body: EntryIn, done: Bool) throws -> WorkoutExercise {
        let ex = try find(body.exercise)
        var e = WorkoutExercise(exerciseId: ex.id, note: body.note ?? "")
        for (name, value) in body.settings ?? [:] {
            guard let c = ex.settings.first(where: { $0.name.lowercased() == name.lowercased() }) else {
                throw HTTPError(.badRequest, message: "\(ex.name) has no setting \"\(name)\". It has: "
                    + (ex.settings.isEmpty ? "none (add them with slam_update_exercise)" : ex.settings.map(\.name).joined(separator: ", ")))
            }
            e[setting: c.id] = value
        }
        e.sets = (body.sets ?? []).map { s in
            var set = WorkSet(kind: s.kind ?? .normal)
            set.kg = s.kg
            set.reps = s.reps
            set.repsR = ex.unilateral ? (s.repsRight ?? s.reps) : nil
            set.rir = set.kind == .warmup ? nil : s.rir
            set.rirR = ex.unilateral && set.kind != .warmup ? (s.rirRight ?? s.rir) : nil
            set.seconds = s.seconds
            set.meters = s.meters
            if let kg = s.kg, ex.type.hasKg { set.load = Load.guess(kg, ex) }
            set.done = done
            return set
        }
        return e
    }

    func exercise(_ body: ExerciseIn) throws -> Exercise {
        var e: Exercise
        if let id = body.id {
            guard let have = byId[id] else { throw HTTPError(.notFound, message: "No exercise with id \(id).") }
            e = have
        } else {
            let name = body.name?.trimmingCharacters(in: .whitespaces) ?? ""
            guard !name.isEmpty else { throw HTTPError(.badRequest, message: "Give the exercise's id to change it, or a name to add one.") }
            guard !lib.exercises.contains(where: { $0.name.lowercased() == name.lowercased() }) else {
                throw HTTPError(.conflict, message: "\(name) already exists; pass its id to change it.")
            }
            e = Exercise(name: name)
        }
        if let v = body.name?.trimmingCharacters(in: .whitespaces), !v.isEmpty { e.name = v }
        if let v = body.type { e.type = v }
        if let v = body.equipment { e.equipment = v }
        if let v = body.primary { e.primary = v }
        if let v = body.secondary { e.secondary = v }
        if let v = body.unilateral { e.unilateral = v }
        if let v = body.brand { e.brand = v }
        if let v = body.stack { e.stack = v.sorted() }
        if let r = body.stackRange {
            let slots = Exercise.slots(from: r.from, step: r.step, to: r.to)
            guard !slots.isEmpty else { throw HTTPError(.badRequest, message: "stack_range gives no slots.") }
            e.stack = slots
        }
        if let v = body.addOn { e.addOn = v > 0 ? v : nil }
        if let v = body.pin { e.pin = v }
        if let v = body.bar { e.bar = v > 0 ? v : nil }
        if let v = body.plateSides {
            guard (0...2).contains(v) else { throw HTTPError(.badRequest, message: "plate_sides is 0, 1 or 2.") }
            e.plateSides = v
        }
        if let list = body.settings {
            e.settings = list.map { s in
                var c = e.settings.first { $0.name.lowercased() == s.name.lowercased() } ?? Configurable(name: s.name)
                c.name = s.name
                if let p = s.perWorkout { c.perWorkout = p }
                return c
            }
        }
        return e
    }

    func newWorkout(_ body: WorkoutIn) throws -> Workout {
        guard body.start < Date() else { throw HTTPError(.badRequest, message: "Only workouts that already happened can be logged.") }
        if body.confirm != true, let near = lib.workouts.first(where: { abs($0.start.timeIntervalSince(body.start)) < 7200 }) {
            throw HTTPError(.conflict, message: "\"\(near.title)\" (\(near.id)) already starts within two hours of this. "
                + "If this is really another workout, send confirm=true.")
        }
        let end = try self.end(body.start, body.end, body.minutes)
        var w = Workout(title: body.title, start: body.start, end: end, notes: body.notes ?? "", gymId: try gymId(body.gym))
        if let r = body.routine {
            guard let routine = lib.routines.first(where: { $0.name.lowercased() == r.lowercased() }) else {
                throw HTTPError(.badRequest, message: "No routine called \(r).")
            }
            w.routineId = routine.id
        }
        w.exercises = try body.exercises.map { try entry($0, done: true) }
        stampDone(&w)
        return w
    }

    func change(_ current: Workout, _ body: WorkoutChange) throws -> Workout {
        var w = current
        if let v = body.title { w.title = v }
        if let v = body.notes { w.notes = v }
        if let v = body.start {
            let length = w.duration
            w.start = v
            if body.end == nil { w.end = v.addingTimeInterval(length) }
        }
        if let v = body.end {
            guard v > w.start else { throw HTTPError(.badRequest, message: "end must be after start.") }
            w.end = v
        }
        if body.gym != nil { w.gymId = try gymId(body.gym) }
        if let list = body.exercises {
            w.exercises = try list.map { try entry($0, done: true) }
            stampDone(&w)
        }
        return w
    }

    private func end(_ start: Date, _ end: Date?, _ minutes: Int?) throws -> Date {
        if let end {
            guard end > start else { throw HTTPError(.badRequest, message: "end must be after start.") }
            return end
        }
        guard let minutes, minutes > 0 else { throw HTTPError(.badRequest, message: "Give end or minutes.") }
        return start.addingTimeInterval(Double(minutes) * 60)
    }

    private func gymId(_ name: String?) throws -> UUID? {
        guard let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
        guard let g = lib.gyms.first(where: { $0.name.lowercased() == name.lowercased() }) else {
            throw HTTPError(.badRequest, message: "No gym called \(name). Gyms: " + lib.gyms.map(\.name).joined(separator: ", "))
        }
        return g.id
    }

    /// Sets spread evenly through the workout, as if ticked as they were done.
    private func stampDone(_ w: inout Workout) {
        let count = w.exercises.reduce(0) { $0 + $1.sets.count }
        guard count > 0, let end = w.end else { return }
        let step = end.timeIntervalSince(w.start) / Double(count + 1)
        var n = 0
        for i in w.exercises.indices {
            for j in w.exercises[i].sets.indices {
                n += 1
                w.exercises[i].sets[j].doneAt = w.start.addingTimeInterval(step * Double(n))
            }
        }
    }
}
