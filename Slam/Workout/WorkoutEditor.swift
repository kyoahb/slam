import SwiftUI
import SlamCore

enum EditorMode {
    /// The workout in progress.
    case live
    /// A finished workout being edited.
    case past
    /// A routine: sets are a template, the note is the long-term one.
    case routine
}

enum Field: Hashable {
    case kg, reps, repsR, time, distance, stack, addOn

    var isWeight: Bool { self == .kg || self == .stack || self == .addOn }
    var allowsDot: Bool { isWeight || self == .distance }
}

struct Cell: Hashable {
    var entry: UUID
    var set: UUID
    var field: Field
}

struct SetRef: Identifiable, Hashable {
    var entry: UUID
    var set: UUID
    var id: UUID { set }
}

struct EntryRef: Identifiable, Hashable {
    var id: UUID
}

enum Key {
    case digit(Int), dot, back
}

/// Editing state for one workout or routine: values, the selected cell and the keypad.
@Observable @MainActor
final class WorkoutEditor: Identifiable {
    let id = UUID()
    var workout: Workout
    let mode: EditorMode
    let app: AppModel

    private(set) var focus: Cell?
    private(set) var draft: String?
    var picking = false
    var replacing: EntryRef?
    var reordering = false
    var settingsFor: EntryRef?
    var editingExercise: ExerciseLink?
    var saving = false
    var doneTick = 0
    var folderId: UUID?
    var isNew = false

    @ObservationIgnored private var typingFrom: WorkSet?
    @ObservationIgnored private var lastCache: [UUID: WorkoutExercise?] = [:]
    @ObservationIgnored private var plateCache: [UUID: Double?] = [:]

    struct Pos {
        var e: Int
        var s: Int
    }

    init(workout: Workout, mode: EditorMode, app: AppModel) {
        self.workout = workout
        self.mode = mode
        self.app = app
    }

    var showsTicks: Bool { mode != .routine }

    // MARK: Lookups

    func exercise(_ e: WorkoutExercise) -> Exercise {
        app.byId[e.exerciseId] ?? Exercise(id: e.exerciseId, name: "Deleted exercise")
    }

    func exercise(entry id: UUID) -> Exercise? {
        entry(id).map(exercise)
    }

    func entry(_ id: UUID) -> WorkoutExercise? {
        workout.exercises.first { $0.id == id }
    }

    func set(_ c: Cell) -> WorkSet? {
        entry(c.entry)?.sets.first { $0.id == c.set }
    }

    private func pos(_ entry: UUID, _ set: UUID? = nil) -> Pos? {
        guard let e = workout.exercises.firstIndex(where: { $0.id == entry }) else { return nil }
        guard let set else { return Pos(e: e, s: -1) }
        guard let s = workout.exercises[e].sets.firstIndex(where: { $0.id == set }) else { return nil }
        return Pos(e: e, s: s)
    }

    /// Last time's entry for this exercise.
    func last(_ e: WorkoutExercise) -> WorkoutExercise? {
        if let hit = lastCache[e.exerciseId] { return hit }
        let found = app.lastTime(e.exerciseId, excluding: mode == .routine ? nil : workout.id,
                                 before: mode == .past ? workout.start : nil)
        lastCache[e.exerciseId] = .some(found)
        return found
    }

    /// Grey values for each set: last time's matching set, else the routine's target.
    func placeholders(_ e: WorkoutExercise) -> [WorkSet?] {
        var out = Previous.match(e.sets, last: last(e)?.sets ?? [])
        if mode != .routine, let targets = app.routine(workout.routineId)?.exercises.first(where: { $0.exerciseId == e.exerciseId })?.sets {
            let t = Previous.match(e.sets, last: targets)
            for i in out.indices where out[i] == nil { out[i] = t[i] }
        }
        return out
    }

    func placeholder(_ c: Cell) -> WorkSet? {
        guard let e = entry(c.entry), let i = e.sets.firstIndex(where: { $0.id == c.set }) else { return nil }
        return placeholders(e)[i]
    }

    func longNote(_ e: WorkoutExercise) -> String {
        mode == .routine ? "" : app.longNote(e.exerciseId, routineId: workout.routineId)
    }

    func maxPlate(_ exerciseId: UUID) -> Double? {
        if let hit = plateCache[exerciseId] { return hit }
        let found = app.maxPlate(exerciseId)
        plateCache[exerciseId] = .some(found)
        return found
    }

    func fields(_ ex: Exercise) -> [Field] {
        var f: [Field] = []
        if ex.type.hasKg { f.append(.kg) }
        if ex.type.hasReps {
            f.append(.reps)
            if ex.unilateral { f.append(.repsR) }
        }
        if ex.type.hasDistance { f.append(.distance) }
        if ex.type.hasTime { f.append(.time) }
        return f
    }

    /// The weight's parts: typed, else last time's, else the whole weight as the stack.
    func load(_ c: Cell) -> Load? {
        guard let s = set(c) else { return nil }
        if let l = s.load { return l }
        let p = placeholder(c)
        if s.kg == nil, let l = p?.load { return l }
        if let kg = s.kg ?? p?.kg { return Load(base: kg) }
        return nil
    }

    /// Whether `load(c)` is only last time's, not yet this set's.
    func loadIsPlaceholder(_ c: Cell) -> Bool {
        guard let s = set(c) else { return true }
        return s.load == nil && s.kg == nil
    }

    func tidySuggestion(_ c: Cell) -> [Double]? {
        guard let l = load(c), let ex = exercise(entry: c.entry) else { return nil }
        return Plates.tidy(l.plates, available: app.settings.plates, maxPlate: maxPlate(ex.id))
    }

    // MARK: Changes

    private func write(_ p: Pos, _ s: WorkSet) {
        workout.exercises[p.e].sets[p.s] = s
        changed()
    }

    func changed() {
        if mode == .live { app.saveActive(workout) }
    }

    func addSet(_ entry: UUID) {
        guard let p = pos(entry) else { return }
        workout.exercises[p.e].sets.append(WorkSet(kind: .normal))
        changed()
    }

    func setKind(_ ref: SetRef, _ kind: SetKind) {
        guard let p = pos(ref.entry, ref.set) else { return }
        var s = workout.exercises[p.e].sets[p.s]
        s.kind = kind
        if kind == .warmup {
            s.rir = nil
            s.rirR = nil
        }
        write(p, s)
    }

    func removeSet(_ ref: SetRef) {
        guard let p = pos(ref.entry, ref.set) else { return }
        if focus?.set == ref.set { select(nil) }
        workout.exercises[p.e].sets.remove(at: p.s)
        changed()
    }

    /// Ticking takes anything not typed from last time, then starts the rest timer.
    func toggleDone(_ entry: UUID, _ set: UUID) {
        guard let p = pos(entry, set) else { return }
        var s = workout.exercises[p.e].sets[p.s]
        if s.done {
            s.done = false
            s.doneAt = nil
            write(p, s)
            return
        }
        s = s.filled(from: placeholders(workout.exercises[p.e])[p.s])
        guard !s.isEmpty else { return }
        s.done = true
        s.doneAt = Date()
        if focus?.set == set { select(nil) }
        write(p, s)
        doneTick += 1
        if mode == .live, let rest = Rest.after(p.s, in: workout.exercises[p.e].sets, settings: app.settings) {
            app.startRest(rest)
        }
    }

    // MARK: Keypad

    func select(_ cell: Cell?) {
        focus = cell
        draft = nil
        typingFrom = nil
        if cell != nil {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }

    /// The value as it would be typed.
    func raw(_ c: Cell) -> String {
        guard let s = set(c) else { return "" }
        switch c.field {
        case .kg: return s.kg.map { Format.kg($0) } ?? ""
        case .reps: return s.reps.map { String($0) } ?? ""
        case .repsR: return s.repsR.map { String($0) } ?? ""
        case .time: return s.seconds.map { Format.digits(fromSeconds: $0) } ?? ""
        case .distance: return s.meters.map { distanceText($0, entry: c.entry) } ?? ""
        case .stack: return load(c).map { Format.kg($0.base) } ?? ""
        case .addOn: return load(c).map { Format.kg($0.addOn) } ?? ""
        }
    }

    /// What a cell shows: the typed text while typing, else the value; nil when empty.
    func text(_ c: Cell) -> String? {
        if focus == c, let draft {
            if c.field == .time { return Format.secondsFromDigits(draft).map { Format.clock($0) } ?? "" }
            return draft
        }
        guard let s = set(c) else { return nil }
        switch c.field {
        case .kg: return s.kg.map { Format.kg($0) }
        case .reps: return s.reps.map { String($0) }
        case .repsR: return s.repsR.map { String($0) }
        case .time: return s.seconds.map { Format.clock($0) }
        case .distance: return s.meters.map { distanceText($0, entry: c.entry) }
        case .stack, .addOn: return raw(c)
        }
    }

    func placeholderText(_ c: Cell) -> String? {
        guard let p = placeholder(c) else { return nil }
        switch c.field {
        case .kg: return p.kg.map { Format.kg($0) }
        case .reps: return p.reps.map { String($0) }
        case .repsR: return p.repsR.map { String($0) }
        case .time: return p.seconds.map { Format.clock($0) }
        case .distance: return p.meters.map { distanceText($0, entry: c.entry) }
        case .stack, .addOn: return nil
        }
    }

    func usesKm(_ entry: UUID) -> Bool { exercise(entry: entry)?.type == .distanceDuration }

    private func distanceText(_ meters: Double, entry: UUID) -> String {
        usesKm(entry) ? Format.km(meters) : Format.kg(meters)
    }

    func key(_ k: Key) {
        guard let c = focus, let s = set(c) else { return }
        if draft == nil { typingFrom = s }
        let started = draft != nil
        var text = draft ?? ""
        switch k {
        case .digit(let d):
            text = started ? text + String(d) : String(d)
        case .dot:
            guard c.field.allowsDot else { return }
            if !started {
                text = "0."
            } else if !text.contains(".") {
                text += "."
            }
        case .back:
            text = String((started ? text : raw(c)).dropLast())
        }
        guard text.count <= 7 else { return }
        draft = text
        apply(c, text)
    }

    private func apply(_ c: Cell, _ text: String) {
        guard let p = pos(c.entry, c.set), let ex = exercise(entry: c.entry) else { return }
        var s = workout.exercises[p.e].sets[p.s]
        let number = Double(text)
        switch c.field {
        case .kg:
            s.kg = number
            let from = typingFrom?.load ?? (typingFrom?.kg == nil ? placeholder(c)?.load : nil)
            if ex.load == .plain || number == nil || from == nil {
                s.load = nil
            } else if let from, let number {
                s.load = from.retargeted(to: number, kind: ex.load, available: app.settings.plates,
                                         maxPlate: maxPlate(ex.id))
            }
        case .reps: s.reps = Int(text)
        case .repsR: s.repsR = Int(text)
        case .time: s.seconds = Format.secondsFromDigits(text)
        case .distance: s.meters = number.map { usesKm(c.entry) ? $0 * 1000 : $0 }
        case .stack, .addOn:
            var l = typingFrom.flatMap { $0.load } ?? load(c) ?? Load()
            if c.field == .stack { l.base = number ?? 0 } else { l.addOn = number ?? 0 }
            s.load = l
            s.kg = l.total(ex.load)
        }
        write(p, s)
    }

    func next() {
        guard let c = focus, let p = pos(c.entry, c.set) else { return }
        let e = workout.exercises[p.e]
        let fs = fields(exercise(e))
        let field: Field = c.field.isWeight ? .kg : c.field
        if let i = fs.firstIndex(of: field), i + 1 < fs.count {
            select(Cell(entry: c.entry, set: c.set, field: fs[i + 1]))
        } else if p.s + 1 < e.sets.count, let first = fs.first {
            select(Cell(entry: c.entry, set: e.sets[p.s + 1].id, field: first))
        } else {
            select(nil)
        }
    }

    func rir(_ c: Cell) -> Int? {
        guard let s = set(c) else { return nil }
        return c.field == .repsR ? s.rirR : s.rir
    }

    func setRIR(_ value: Int?) {
        guard let c = focus, let p = pos(c.entry, c.set) else { return }
        var s = workout.exercises[p.e].sets[p.s]
        guard s.kind != .warmup else { return }
        if c.field == .repsR { s.rirR = value } else { s.rir = value }
        write(p, s)
    }

    // MARK: Weight card

    /// Weight and plates from the set above (or its grey value).
    func sameAsAbove(_ c: Cell) {
        guard let p = pos(c.entry, c.set), p.s > 0 else { return }
        let e = workout.exercises[p.e]
        let ph = placeholders(e)
        var source: WorkSet?
        for j in stride(from: p.s - 1, through: 0, by: -1) {
            if e.sets[j].kg != nil { source = e.sets[j]; break }
            if let x = ph[j], x.kg != nil { source = x; break }
        }
        guard let source else { return }
        var s = e.sets[p.s]
        s.kg = source.kg
        s.load = source.load
        draft = nil
        write(p, s)
    }

    func bump(_ c: Cell, by delta: Double) {
        guard let p = pos(c.entry, c.set) else { return }
        var s = workout.exercises[p.e].sets[p.s]
        let start = s.kg ?? placeholder(c)?.kg ?? 0
        s.kg = max(0, ((start + delta) * 100).rounded() / 100)
        s.load = nil
        draft = nil
        write(p, s)
    }

    func addPlate(_ c: Cell, _ plate: Double) {
        guard let p = pos(c.entry, c.set), let ex = exercise(entry: c.entry) else { return }
        let l = (load(c) ?? Load()).adding(plate)
        var s = workout.exercises[p.e].sets[p.s]
        s.load = l
        s.kg = l.total(ex.load)
        draft = nil
        write(p, s)
    }

    func removePlate(_ c: Cell, at index: Int) {
        guard let p = pos(c.entry, c.set), let ex = exercise(entry: c.entry), let current = load(c) else { return }
        let l = current.removingPlate(at: index)
        var s = workout.exercises[p.e].sets[p.s]
        s.load = l
        s.kg = l.total(ex.load)
        draft = nil
        write(p, s)
    }

    func tidy(_ c: Cell) {
        guard let p = pos(c.entry, c.set), let ex = exercise(entry: c.entry), var l = load(c),
              let plates = tidySuggestion(c) else { return }
        l.plates = plates
        var s = workout.exercises[p.e].sets[p.s]
        s.load = l
        s.kg = l.total(ex.load)
        draft = nil
        write(p, s)
    }

    func editPart(_ c: Cell, _ field: Field) {
        select(Cell(entry: c.entry, set: c.set, field: field))
    }

    // MARK: Exercises

    func add(_ list: [Exercise]) {
        for ex in list {
            let previous = app.lastTime(ex.id, excluding: workout.id, before: mode == .past ? workout.start : nil)
            lastCache[ex.id] = .some(previous)
            var e = WorkoutExercise.adding(ex, last: previous)
            if mode == .past {
                for i in e.sets.indices { e.sets[i].done = false }
            }
            workout.exercises.append(e)
        }
        changed()
    }

    func replace(_ entry: UUID, with ex: Exercise) {
        guard let p = pos(entry) else { return }
        if focus?.entry == entry { select(nil) }
        var e = workout.exercises[p.e]
        e.exerciseId = ex.id
        e.note = ""
        e.settings = [:]
        e.sets = e.sets.map { WorkSet(kind: $0.kind) }
        lastCache[ex.id] = .some(app.lastTime(ex.id, excluding: workout.id, before: mode == .past ? workout.start : nil))
        e.carrySettings(ex, last: lastCache[ex.id] ?? nil)
        workout.exercises[p.e] = e
        changed()
    }

    func remove(_ entry: UUID) {
        if focus?.entry == entry { select(nil) }
        workout.exercises.removeAll { $0.id == entry }
        changed()
    }

    func move(from: IndexSet, to: Int) {
        workout.exercises.move(fromOffsets: from, toOffset: to)
        changed()
    }

    func setNote(_ entry: UUID, _ text: String) {
        guard let p = pos(entry) else { return }
        workout.exercises[p.e].note = text
        changed()
    }

    func setting(_ entry: UUID, _ id: UUID) -> String {
        self.entry(entry)?[setting: id] ?? ""
    }

    func setSetting(_ entry: UUID, _ id: UUID, _ value: String) {
        guard let p = pos(entry) else { return }
        workout.exercises[p.e][setting: id] = value
        changed()
    }

    // MARK: Finishing

    var doneCount: Int { workout.exercises.reduce(0) { $0 + $1.sets.filter(\.done).count } }

    /// Sets with something typed that were never ticked.
    var unfinished: Int {
        workout.exercises.reduce(0) { $0 + $1.sets.filter { !$0.done && !$0.isEmpty }.count }
    }

    func completeUnfinished() {
        for i in workout.exercises.indices {
            let ph = placeholders(workout.exercises[i])
            for j in workout.exercises[i].sets.indices where !workout.exercises[i].sets[j].done
                && !workout.exercises[i].sets[j].isEmpty {
                var s = workout.exercises[i].sets[j].filled(from: ph[j])
                s.done = true
                s.doneAt = Date()
                workout.exercises[i].sets[j] = s
            }
        }
        changed()
    }

    /// The workout as it gets saved: only ticked sets (any typed set, when editing a past one).
    func cleaned() -> Workout {
        var w = workout
        for i in w.exercises.indices {
            if mode == .past {
                w.exercises[i].sets = w.exercises[i].sets.filter { !$0.isEmpty }
                for j in w.exercises[i].sets.indices { w.exercises[i].sets[j].done = true }
            } else {
                w.exercises[i].sets = w.exercises[i].sets.filter(\.done)
            }
        }
        w.exercises.removeAll { $0.sets.isEmpty }
        return w
    }

    var volume: Double { Stats.volume(workout, app.byId) }
}
