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
    case kg, reps, repsR, time, distance

    var allowsDot: Bool { self == .kg || self == .distance }
}

struct Cell: Hashable {
    var entry: UUID
    var set: UUID
    var field: Field
}

struct SetRef: Identifiable, Hashable {
    var entry: UUID
    var set: UUID
    var id: UUID { self.set }
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
    /// The keypad shows the plates on a stack machine's pin instead of its slots.
    var pinPlates = false
    var picking = false
    var replacing: EntryRef?
    var reordering = false
    var settingsFor: EntryRef?
    var editingExercise: ExerciseLink?
    var saving = false
    var doneTick = 0
    var recordTick = 0
    /// The record banner showing at the top of the live workout.
    var banner: RecordBanner?
    /// Records made so far in this workout, by entry.
    private(set) var liveRecords: [UUID: [Record]] = [:]
    var folderId: UUID?
    var isNew = false

    @ObservationIgnored private var lastCache: [UUID: WorkoutExercise?] = [:]
    @ObservationIgnored private var bestsCache: [UUID: Bests] = [:]

    struct Pos {
        var e: Int
        var s: Int
    }

    init(workout: Workout, mode: EditorMode, app: AppModel) {
        self.workout = workout
        self.mode = mode
        self.app = app
        if mode == .live {
            for e in workout.exercises { liveRecords[e.id] = bests(e.exerciseId).records(e) }
        }
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

    /// A set's weight parts: its own once it has a weight, else last time's.
    func load(_ c: Cell) -> Load? {
        guard let s = set(c) else { return nil }
        if s.kg != nil { return parts(s, c.entry) }
        return placeholder(c).flatMap { parts($0, c.entry) }
    }

    /// The parts of a set's weight; a bare total (typed, or from Hevy) is read as plates where plates go.
    func parts(_ s: WorkSet, _ entry: UUID) -> Load? {
        guard let kg = s.kg else { return nil }
        if let l = s.load { return l }
        return exercise(entry: entry).map { Load.guess(kg, $0) } ?? Load(base: kg)
    }

    /// Before last time's records, what this workout has to beat.
    private func bests(_ exerciseId: UUID) -> Bests {
        if let hit = bestsCache[exerciseId] { return hit }
        let b = Records.bests(exerciseId, type: app.byId[exerciseId]?.type ?? .weightReps, in: app.workouts,
                              excluding: workout.id)
        bestsCache[exerciseId] = b
        return b
    }

    func hasRecord(_ entry: UUID, _ set: UUID) -> Bool {
        liveRecords[entry]?.contains { $0.setId == set } ?? false
    }

    // MARK: Changes

    private func write(_ p: Pos, _ s: WorkSet) {
        workout.exercises[p.e].sets[p.s] = s
        if mode == .live, s.done || liveRecords[workout.exercises[p.e].id] != nil {
            let e = workout.exercises[p.e]
            liveRecords[e.id] = bests(e.exerciseId).records(e)
        }
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
        if mode == .live {
            let e = workout.exercises[p.e]
            let news = bests(e.exerciseId).news(e, set: set)
            if !news.isEmpty {
                banner = RecordBanner(exercise: exercise(e), items: news)
                recordTick += 1
            }
            if !app.demo { Sounds.play(news.isEmpty ? .set : .record) }
        }
        if mode == .live, let rest = Rest.after(p.s, in: workout.exercises[p.e].sets, settings: app.settings) {
            app.startRest(rest)
        }
    }

    // MARK: Keypad

    func select(_ cell: Cell?) {
        if cell?.set != focus?.set { pinPlates = false }
        focus = cell
        draft = nil
        if cell != nil {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }

    /// What the weight cell shows and the digits type.
    private func typedKg(_ s: WorkSet, _ entry: UUID) -> Double? {
        s.shownKg(exercise(entry: entry)?.rig ?? .plain)
    }

    /// The value as it would be typed.
    func raw(_ c: Cell) -> String {
        guard let s = set(c) else { return "" }
        switch c.field {
        case .kg: return typedKg(s, c.entry).map { Format.kg($0) } ?? ""
        case .reps: return s.reps.map { String($0) } ?? ""
        case .repsR: return s.repsR.map { String($0) } ?? ""
        case .time: return s.seconds.map { Format.digits(fromSeconds: $0) } ?? ""
        case .distance: return s.meters.map { distanceText($0, entry: c.entry) } ?? ""
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
        case .kg: return typedKg(s, c.entry).map { Format.kg($0) }
        case .reps: return s.reps.map { String($0) }
        case .repsR: return s.repsR.map { String($0) }
        case .time: return s.seconds.map { Format.clock($0) }
        case .distance: return s.meters.map { distanceText($0, entry: c.entry) }
        }
    }

    func placeholderText(_ c: Cell) -> String? {
        guard let p = placeholder(c) else { return nil }
        switch c.field {
        case .kg: return typedKg(p, c.entry).map { Format.kg($0) }
        case .reps: return p.reps.map { String($0) }
        case .repsR: return p.repsR.map { String($0) }
        case .time: return p.seconds.map { Format.clock($0) }
        case .distance: return p.meters.map { distanceText($0, entry: c.entry) }
        }
    }

    func usesKm(_ entry: UUID) -> Bool { exercise(entry: entry)?.type == .distanceDuration }

    private func distanceText(_ meters: Double, entry: UUID) -> String {
        usesKm(entry) ? Format.km(meters) : Format.kg(meters)
    }

    func key(_ k: Key) {
        guard let c = focus, set(c) != nil else { return }
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
        guard let p = pos(c.entry, c.set) else { return }
        var s = workout.exercises[p.e].sets[p.s]
        let number = Double(text)
        switch c.field {
        case .kg:
            // On a stack or a dumbbell the digits set the slot or dumbbell; the add-on and plates stay.
            if let number, let ex = exercise(entry: c.entry), ex.rig == .stack || ex.rig == .dumbbell {
                var l = seed(c, ex)
                l.base = number
                s.load = l
                s.kg = l.total
            } else {
                s.kg = number
                s.load = nil
            }
        case .reps: s.reps = Int(text)
        case .repsR: s.repsR = Int(text)
        case .time: s.seconds = Format.secondsFromDigits(text)
        case .distance: s.meters = number.map { usesKm(c.entry) ? $0 * 1000 : $0 }
        }
        write(p, s)
    }

    func next() {
        guard let c = focus, let p = pos(c.entry, c.set) else { return }
        let e = workout.exercises[p.e]
        let fs = fields(exercise(e))
        if let i = fs.firstIndex(of: c.field), i + 1 < fs.count {
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

    // MARK: Weight parts
    // Each control changes one part; the rest stay as they were, or as last time when nothing is set yet.

    /// What a change starts from: the set's parts, else last time's, else the bare bar or an empty stack.
    private func seed(_ c: Cell, _ ex: Exercise) -> Load {
        var l = load(c) ?? ex.emptyLoad
        l.sides = ex.sides
        return l
    }

    private func change(_ edit: (inout Load, Exercise) -> Void) {
        guard let c = focus, let p = pos(c.entry, c.set), let ex = exercise(entry: c.entry) else { return }
        var s = workout.exercises[p.e].sets[p.s]
        var l = seed(c, ex)
        edit(&l, ex)
        s.load = l
        s.kg = max(0, l.total)
        draft = nil
        write(p, s)
    }

    /// Picks a stack slot. Picking the set's own slot again clears its weight.
    func pickSlot(_ slot: Double) {
        guard let c = focus, let p = pos(c.entry, c.set) else { return }
        let s = workout.exercises[p.e].sets[p.s]
        if s.kg != nil, let own = s.load?.base, abs(own - slot) < 0.01 {
            clearWeight()
            return
        }
        change { l, _ in l.base = slot }
    }

    func toggleAddOn() {
        change { l, ex in l.addOn = l.addOn > 0 ? 0 : (ex.addOn ?? 0) }
    }

    func addPlate(_ plate: Double) {
        change { l, _ in
            l.plates.append(plate)
            l.plates.sort(by: >)
        }
    }

    func removePlate(at index: Int) {
        change { l, _ in if l.plates.indices.contains(index) { l.plates.remove(at: index) } }
    }

    func clearPlates() {
        change { l, _ in l.plates = [] }
    }

    /// A dumbbell's small plates go on and off with one tap each.
    func toggleMicro(_ plate: Double) {
        change { l, _ in
            if let i = l.plates.firstIndex(where: { abs($0 - plate) < 0.01 }) { l.plates.remove(at: i) } else { l.plates.append(plate) }
            l.plates.sort(by: >)
        }
    }

    /// Back to last time's weight.
    func clearWeight() {
        guard let c = focus, let p = pos(c.entry, c.set) else { return }
        var s = workout.exercises[p.e].sets[p.s]
        s.kg = nil
        s.load = nil
        draft = nil
        write(p, s)
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
