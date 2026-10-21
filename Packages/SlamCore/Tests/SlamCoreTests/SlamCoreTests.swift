import XCTest
@testable import SlamCore

final class StackTests: XCTestCase {
    func testSlots() {
        XCTAssertEqual(Exercise.slots(from: 5, step: 5, to: 20), [5, 10, 15, 20])
        XCTAssertEqual(Exercise.slots(from: 2.5, step: 2.5, to: 9), [2.5, 5, 7.5])
        XCTAssertEqual(Exercise.slots(from: 10, step: 0, to: 20), [])
        XCTAssertEqual(Exercise.slots(from: 4, step: 7, to: 109).last, 109)
    }

    func testFilledTakesLastTimesParts() {
        let prev = WorkSet(kg: 97, reps: 8, load: Load(base: 90, addOn: 2, plates: [5]))
        let fresh = WorkSet().filled(from: prev)
        XCTAssertEqual(fresh.kg, 97)
        XCTAssertEqual(fresh.load, prev.load)
    }
}

final class LoadTests: XCTestCase {
    func testRigFollowsEquipment() {
        XCTAssertEqual(Exercise(name: "Leg Extension").rig, .stack)
        XCTAssertEqual(Exercise(name: "Cable Row", equipment: .cable).rig, .stack)
        XCTAssertEqual(Exercise(name: "Leg Press", plateSides: 2).rig, .plateLoaded)
        XCTAssertEqual(Exercise(name: "Squat", equipment: .barbell).rig, .barbell)
        XCTAssertEqual(Exercise(name: "Curl", equipment: .dumbbell).rig, .dumbbell)
        XCTAssertEqual(Exercise(name: "Kettlebell Swing", equipment: .kettlebell).rig, .plain)
        XCTAssertEqual(Exercise(name: "Pull Up", type: .repsOnly).rig, .plain)
        XCTAssertEqual(Exercise(name: "Cable Row", equipment: .cable, plateSides: 2).rig, .stack)
    }

    func testBarWeightAndSides() {
        let squat = Exercise(name: "Squat", equipment: .barbell)
        XCTAssertEqual(squat.barWeight, 20)
        XCTAssertEqual(squat.sides, 2)
        XCTAssertEqual(squat.emptyLoad, Load(base: 20, sides: 2))
        XCTAssertEqual(Exercise(name: "EZ Curl", equipment: .barbell, bar: 10).barWeight, 10)
        XCTAssertEqual(Exercise(name: "T Bar", plateSides: 1).emptyLoad, Load(base: 0, sides: 1))
    }

    func testTotalsAndSummaries() {
        let pin = Load(base: 109, addOn: 2, plates: [5, 2.5])
        XCTAssertEqual(pin.total, 118.5)
        XCTAssertEqual(pin.summary(.stack), "109 +2 pin 5 2.5")
        XCTAssertEqual(Load(base: 109).summary(.stack), nil)
        XCTAssertEqual(Load(base: 109, addOn: 2).summary(.stack), "109 +2")
        let bar = Load(base: 20, plates: [20, 10], sides: 2)
        XCTAssertEqual(bar.total, 80)
        XCTAssertEqual(bar.summary(.barbell), "20 10 a side")
        XCTAssertEqual(Load(base: 0, plates: [20, 20], sides: 1).summary(.plateLoaded), "20 20")
        XCTAssertEqual(Load(base: 0, plates: [20, 20, 20, 20, 5], sides: 1).summary(.plateLoaded), "4×20 5")
        XCTAssertEqual(Load(base: 22.5, plates: [1]).summary(.dumbbell), "22.5 +1")
        XCTAssertNil(Load(base: 22.5).summary(.dumbbell))
    }

    func testGuessMakesTheTotalFromPlates() {
        let squat = Exercise(name: "Squat", equipment: .barbell)
        XCTAssertEqual(Load.guess(100, squat), Load(base: 20, plates: [20, 20], sides: 2))
        XCTAssertEqual(Load.guess(62.5, squat).plates, [20, 1.25])
        // What plates cannot make stays in the base: the total never changes.
        XCTAssertEqual(Load.guess(61, squat).total, 61)
        XCTAssertEqual(Load.guess(15, squat), Load(base: 15, sides: 2))
        XCTAssertEqual(Plates.make(37.5), [20, 15, 2.5])
    }

    func testOldAddOnLoads() throws {
        let json = #"{"id":"7C9E6679-7425-40DE-944B-E07FC1F90AE7","kg":111,"reps":8,"addOn":2,"done":true}"#
        let set = try FileStore.decoder.decode(WorkSet.self, from: Data(json.utf8))
        XCTAssertEqual(set.load, Load(base: 109, addOn: 2))
        let again = try FileStore.decoder.decode(WorkSet.self, from: FileStore.encoder.encode(set))
        XCTAssertEqual(again.load, set.load)
    }
}

final class PreviousTests: XCTestCase {
    func testMatchesByKindAndPosition() {
        let last = [WorkSet(kind: .warmup, kg: 50, reps: 10), WorkSet(kg: 100, reps: 8), WorkSet(kg: 95, reps: 8),
                    WorkSet(kind: .drop, kg: 70, reps: 9)]
        let now = [WorkSet(kind: .warmup), WorkSet(), WorkSet(), WorkSet(), WorkSet(kind: .drop)]
        let m = Previous.match(now, last: last)
        XCTAssertEqual(m.map { $0?.kg }, [50, 100, 95, 95, 70])
    }

    func testLabels() {
        let sets = [WorkSet(kind: .warmup), WorkSet(), WorkSet(), WorkSet(kind: .drop), WorkSet()]
        XCTAssertEqual(Previous.labels(sets), ["W", "1", "2", "D", "3"])
    }

    func testFilledTakesOnlyMissingValues() {
        let prev = WorkSet(kg: 102, reps: 8, rir: 2, load: Load(base: 100, addOn: 2))
        let typed = WorkSet(kg: 102.5).filled(from: prev)
        XCTAssertEqual(typed.kg, 102.5)
        XCTAssertNil(typed.load)
        XCTAssertEqual(typed.reps, 8)
        XCTAssertEqual(typed.rir, 2)
        let warm = WorkSet(kind: .warmup).filled(from: prev)
        XCTAssertNil(warm.rir)
    }

    func testRestRules() {
        let s = Settings(restSeconds: 150, warmupRestSeconds: 45)
        let sets = [WorkSet(kind: .warmup), WorkSet(), WorkSet(kind: .drop), WorkSet()]
        XCTAssertEqual(Rest.after(0, in: sets, settings: s), 45)
        XCTAssertNil(Rest.after(1, in: sets, settings: s))
        XCTAssertEqual(Rest.after(2, in: sets, settings: s), 150)
        XCTAssertEqual(Rest.after(3, in: sets, settings: s), 150)
    }
}

final class RecordTests: XCTestCase {
    func session(_ sets: [(Double, Int)]) -> WorkoutExercise {
        WorkoutExercise(exerciseId: UUID(), sets: sets.map { WorkSet(kg: $0.0, reps: $0.1, done: true) })
    }

    func testSecondSetRecordCountsEvenWhenNotBestOverall() {
        var b = Bests(type: .weightReps)
        b.add(session([(100, 10), (90, 8)]))
        // Set 2 beats last set 2 (90×8) but not set 1 (100×10).
        let r = b.records(session([(100, 10), (92.5, 8)]))
        XCTAssertEqual(r.map(\.kind), [.sessionVolume, .set(1)])
    }

    func testOverallRecordsNotCountedTwice() {
        var b = Bests(type: .weightReps)
        b.add(session([(100, 10), (90, 8)]))
        let r = b.records(session([(105, 10), (90, 8)])).map(\.kind)
        XCTAssertTrue(r.contains(.heaviest))
        XCTAssertTrue(r.contains(.e1rm))
        XCTAssertTrue(r.contains(.setVolume))
        XCTAssertTrue(r.contains(.sessionVolume))
        XCTAssertFalse(r.contains(.set(0)))
    }

    func testLiveNewsComparesWithEarlierSetsToday() {
        var b = Bests(type: .weightReps)
        b.add(session([(97.5, 8), (90, 8)]))
        var today = session([(100, 8), (102.5, 6)])
        today.sets[1].done = false
        // Set 1: heaviest beats history (97.5).
        let first = b.news(today, set: today.sets[0].id)
        XCTAssertEqual(first.first { $0.kind == .heaviest }?.before, 97.5)
        XCTAssertEqual(first.first { $0.kind == .heaviest }?.after, 100)
        // Set 2: heaviest again, now against set 1. Session volume already counted, not new.
        today.sets[1].done = true
        let second = b.news(today, set: today.sets[1].id)
        XCTAssertEqual(second.first { $0.kind == .heaviest }?.before, 100)
        XCTAssertEqual(second.first { $0.kind == .heaviest }?.after, 102.5)
        XCTAssertFalse(second.contains { $0.kind == .sessionVolume })
    }

    func testFirstSessionHasNoRecords() {
        XCTAssertTrue(Bests(type: .weightReps).records(session([(100, 10)])).isEmpty)
    }

    func testUnilateralVolumeCountsBothSides() {
        let s = WorkSet(kg: 50, reps: 10, repsR: 9, done: true)
        XCTAssertEqual(SetMath.volume(s), 950)
        XCTAssertEqual(SetMath.e1rm(WorkSet(kg: 100, reps: 8, rir: 2)) ?? 0, 100 * (1 + 10.0 / 30), accuracy: 0.001)
    }

    func testTrend() {
        let last = session([(100, 10), (90, 8)])
        XCTAssertEqual(Trend.compare(session([(100, 10), (92.5, 8)]), last: last, type: .weightReps), .up)
        XCTAssertEqual(Trend.compare(session([(100, 9), (90, 8)]), last: last, type: .weightReps), .down)
        XCTAssertEqual(Trend.compare(session([(100, 10), (90, 8)]), last: last, type: .weightReps), .same)
    }
}

final class FormatTests: XCTestCase {
    func testNumbers() {
        XCTAssertEqual(Format.kg(121), "121")
        XCTAssertEqual(Format.kg(118.5), "118.5")
        XCTAssertEqual(Format.kg(1.25), "1.25")
        XCTAssertEqual(Format.grouped(12345.4), "12,345")
        XCTAssertEqual(Format.grouped(999), "999")
        XCTAssertEqual(Format.duration(3720), "1h 2min")
        XCTAssertEqual(Format.duration(723), "12min")
        XCTAssertEqual(Format.duration(183), "3min 3s")
        XCTAssertEqual(Format.clock(125), "2:05")
        XCTAssertEqual(Format.secondsFromDigits("130"), 90)
        XCTAssertEqual(Format.secondsFromDigits("10000"), 3600)
        XCTAssertEqual(Format.digits(fromSeconds: 90), "130")
        XCTAssertEqual(Exercise(name: "Deadlift (Barbell)").initials, "DB")
        XCTAssertEqual(Exercise(name: "Precor T Bar Row - Row").initials, "PT")
    }
}

final class StoreTests: XCTestCase {
    func testRoundTripAndOldFilesStillLoad() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileStore(root: dir)
        let lib = Demo.library()
        try store.save(lib)
        let back = try store.load()
        XCTAssertEqual(back.workouts.count, lib.workouts.count)
        XCTAssertEqual(back.workouts.first?.id, lib.workouts.first?.id)
        XCTAssertEqual(back.routines.map(\.name), ["FB A", "FB B", "FB C", "FB D"])
        XCTAssertEqual(back.active?.exercises.first?.sets[1].kg, 111)
        XCTAssertEqual(back.active?.exercises.first?.sets[1].load, Load(base: 109, addOn: 2))
        XCTAssertEqual(back.resolved.first?.stack.count, 16)
        XCTAssertEqual(back.machines, lib.machines)

        // A set written by an older version with fewer keys (and the old plate breakdown).
        let old = #"{"id":"7C9E6679-7425-40DE-944B-E07FC1F90AE7","kg":20,"reps":5,"load":{"base":20,"addOn":0,"plates":[]}}"#
        let set = try FileStore.decoder.decode(WorkSet.self, from: Data(old.utf8))
        XCTAssertEqual(set.kind, .normal)
        XCTAssertFalse(set.done)
        // An exercise from before the pin was kept has none.
        let ex = try FileStore.decoder.decode(Exercise.self, from: Data(#"{"id":"7C9E6679-7425-40DE-944B-E07FC1F90AE7","name":"Row"}"#.utf8))
        XCTAssertFalse(ex.pin)
        XCTAssertTrue(back.resolved.first?.pin ?? false)
    }

    func testWipeKeepsWhatSyncRemembers() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileStore(root: dir)
        let lib = Demo.library()
        try store.save(lib)
        var state = SyncState()
        state.synced = Sync.records(lib).mapValues(\.fingerprint)
        try store.saveSync(state)
        try store.wipe()
        let back = try store.load()
        XCTAssertTrue(back.exercises.isEmpty && back.workouts.isEmpty && back.routines.isEmpty && back.gyms.isEmpty)
        XCTAssertNil(back.active)
        // Every record the server has goes back up as deleted.
        let sent = Sync.changes(back, store.loadSync()) { _ in nil }
        XCTAssertEqual(sent.filter(\.deleted).count, state.synced.count - 1)
    }
}

final class DemoTests: XCTestCase {
    func testDemoHistoryHasRecordsAndWeeks() {
        let lib = Demo.library()
        let byId = Dictionary(uniqueKeysWithValues: lib.resolved.map { ($0.id, $0) })
        XCTAssertGreaterThan(lib.workouts.count, 30)
        let records = Records.all(lib.workouts, exercises: byId)
        XCTAssertGreaterThan(records.values.reduce(0) { $0 + $1.count }, 10)
        let weeks = Stats.weeks(lib.workouts, byId)
        XCTAssertGreaterThanOrEqual(weeks.count, 14)
        XCTAssertGreaterThan(weeks.map(\.volume).max() ?? 0, 0)
        let legExt = lib.exercises[0]
        let series = Stats.series(legExt.id, lib.workouts, metric: .heaviest, type: legExt.type)
        XCTAssertGreaterThan(series.last?.value ?? 0, series.first?.value ?? 0)
        let muscles = Stats.setsPerMuscle(lib.workouts, byId, from: .distantPast, to: .distantFuture)
        XCTAssertFalse(muscles.isEmpty)
        XCTAssertGreaterThan(Stats.weekStreak(lib.workouts.map(\.start)), 0)
    }

    func testRoutineDiffAndApply() {
        let lib = Demo.library()
        let byId = Dictionary(uniqueKeysWithValues: lib.resolved.map { ($0.id, $0) })
        let routine = lib.routines[0]
        var w = Workout.from(routine, exercises: byId, history: lib.workouts, gymId: nil)
        for i in w.exercises.indices { for j in w.exercises[i].sets.indices { w.exercises[i].sets[j].done = true } }
        XCTAssertNil(RoutineDiff.describe(w, routine, byId))
        w.exercises.swapAt(0, 1)
        XCTAssertEqual(RoutineDiff.describe(w, routine, byId), "You reordered your exercises.")
        let updated = RoutineDiff.apply(w, to: routine, byId)
        XCTAssertEqual(updated.exercises.map(\.exerciseId), w.exercises.map(\.exerciseId))
        XCTAssertEqual(updated.exercises[1].note, "seatbelt under legs")
    }
}

final class WatchTests: XCTestCase {
    func testActivitiesFromName() {
        XCTAssertEqual(Exercise(name: "Precor Elliptical", type: .distanceDuration, equipment: .cardio).watchActivities, [.elliptical])
        XCTAssertEqual(Exercise(name: "Treadmill", type: .distanceDuration, equipment: .cardio).watchActivities, [.walking, .running])
        XCTAssertEqual(Exercise(name: "Farmers Walk", type: .weightDuration, equipment: .dumbbell).watchActivities, [])
        XCTAssertEqual(Exercise(name: "Seated Row", type: .weightReps).watchActivities, [])
    }

    func testLinkFillsFirstCardioSetOnce() {
        let row = Exercise(name: "Seated Row")
        let bike = Exercise(name: "Bike", type: .distanceDuration, equipment: .cardio)
        let byId = [row.id: row, bike.id: bike]
        var w = Workout(exercises: [WorkoutExercise(exerciseId: row.id, sets: [WorkSet()]),
                                    WorkoutExercise(exerciseId: bike.id, sets: [WorkSet(seconds: 600)])])
        let start = Date(timeIntervalSince1970: 1000)
        let link = WatchLink(id: UUID(), start: start, end: start.addingTimeInterval(1200), meters: 5000, kcal: 200, heartRate: 140)
        XCTAssertFalse(w.link(link, as: .elliptical, exercises: byId))
        XCTAssertTrue(w.link(link, as: .cycling, exercises: byId))
        XCTAssertFalse(w.link(link, as: .cycling, exercises: byId))
        let s = w.exercises[1].sets[0]
        XCTAssertEqual(s.seconds, 600)
        XCTAssertEqual(s.meters, 5000)
        XCTAssertTrue(s.done)
        XCTAssertEqual(w.exercises[1].watch, link)
        XCTAssertNil(w.exercises[0].watch)
        let back = try! JSONDecoder().decode(Workout.self, from: JSONEncoder().encode(w))
        XCTAssertEqual(back.exercises[1].watch, link)
    }
}

final class SyncTests: XCTestCase {
    private func lib() -> Library {
        let press = Exercise(name: "Leg Press")
        let w = Workout(title: "Legs", start: Date(timeIntervalSince1970: 1_000_000), exercises: [WorkoutExercise(exerciseId: press.id)])
        return Library(exercises: [press], routines: [Routine(name: "Legs")], workouts: [w])
    }

    func testFirstSyncSendsEverythingThenNothing() {
        var l = lib()
        var state = SyncState()
        let sent = Sync.changes(l, state) { _ in nil }
        XCTAssertEqual(Set(sent.map(\.kind)), [.exercise, .routine, .workout, .settings])
        Sync.finish(&l, &state, sent: sent, response: SyncResponse(cursor: 4, changes: []))
        XCTAssertEqual(state.cursor, 4)
        XCTAssertTrue(Sync.changes(l, state) { _ in nil }.isEmpty)
    }

    func testEditsAndDeletesTravel() {
        var l = lib()
        var state = SyncState()
        Sync.finish(&l, &state, sent: Sync.changes(l, state) { _ in nil }, response: SyncResponse(cursor: 4, changes: []))
        l.routines[0].name = "Legs A"
        let gone = l.workouts.removeFirst()
        let sent = Sync.changes(l, state) { _ in nil }
        XCTAssertEqual(sent.count, 2)
        XCTAssertEqual(sent.first { $0.kind == .routine }?.routine?.name, "Legs A")
        XCTAssertTrue(sent.first { $0.kind == .workout }?.deleted ?? false)
        XCTAssertEqual(sent.first { $0.kind == .workout }?.id, gone.id.uuidString)
    }

    func testNewerEditWins() {
        var l = lib()
        var state = SyncState()
        Sync.finish(&l, &state, sent: Sync.changes(l, state) { _ in nil }, response: SyncResponse(cursor: 4, changes: []))
        let routine = l.routines[0]
        var theirs = SyncRecord(kind: .routine, id: routine.id.uuidString, updated: Date(timeIntervalSince1970: 2000), seq: 5)
        theirs.routine = Routine(id: routine.id, name: "Server name")
        // The phone's edit is older: the server's stands.
        l.routines[0].name = "Phone name"
        var sent = Sync.changes(l, state) { _ in Date(timeIntervalSince1970: 1000) }
        Sync.finish(&l, &state, sent: sent, response: SyncResponse(cursor: 5, changes: [theirs]))
        XCTAssertEqual(l.routines[0].name, "Server name")
        XCTAssertTrue(Sync.changes(l, state) { _ in nil }.isEmpty)
        // The phone's edit is newer: it stays.
        l.routines[0].name = "Phone again"
        theirs.routine?.name = "Server again"
        sent = Sync.changes(l, state) { _ in Date(timeIntervalSince1970: 3000) }
        Sync.finish(&l, &state, sent: sent, response: SyncResponse(cursor: 6, changes: [theirs]))
        XCTAssertEqual(l.routines[0].name, "Phone again")
    }

    func testServerDeleteAndActiveIgnored() {
        var l = lib()
        l.active = Workout(title: "Now")
        var state = SyncState()
        Sync.finish(&l, &state, sent: Sync.changes(l, state) { _ in nil }, response: SyncResponse(cursor: 5, changes: []))
        let gone = SyncRecord(kind: .exercise, id: l.exercises[0].id.uuidString, updated: Date(), seq: 6)
        var other = SyncRecord(kind: .active, id: Sync.activeId, updated: Date(), seq: 7)
        other.workout = Workout(title: "Elsewhere")
        Sync.finish(&l, &state, sent: [], response: SyncResponse(cursor: 7, changes: [gone, other]))
        XCTAssertTrue(l.exercises.isEmpty)
        XCTAssertEqual(l.active?.title, "Now")
        XCTAssertTrue(Sync.changes(l, state) { _ in nil }.isEmpty)
    }

    func testRecordsRoundTrip() throws {
        let l = lib()
        var copy = Library()
        for r in Sync.records(l).values {
            let data = try FileStore.encoder.encode(r)
            Sync.apply(try FileStore.decoder.decode(SyncRecord.self, from: data), to: &copy)
        }
        XCTAssertEqual(copy.exercises, l.exercises)
        XCTAssertEqual(copy.workouts, l.workouts)
        XCTAssertEqual(copy.routines, l.routines)
        XCTAssertTrue(Sync.safeFile("A1B2-c3.jpg"))
        XCTAssertFalse(Sync.safeFile("../x.jpg"))
        XCTAssertFalse(Sync.safeFile(".hidden"))
    }
}

final class MachineTests: XCTestCase {
    private let seat = Configurable(name: "Seat")
    private let pad = Configurable(name: "Pad")

    /// An invented leg extension done both legs and one leg, each with its own Seat so far.
    private func lib() -> (Library, Exercise, Exercise) {
        let both = Exercise(name: "Test Leg Extension", stack: Exercise.slots(from: 5, step: 5, to: 50), brand: "Test",
                            settings: [seat])
        let one = Exercise(name: "Test Leg Extension Single", unilateral: true, settings: [Configurable(name: "seat "), pad])
        var e = WorkoutExercise(exerciseId: one.id, sets: [WorkSet(kg: 20, reps: 10, done: true)])
        e[setting: one.settings[0].id] = "4"
        let w = Workout(title: "Legs", start: Date(timeIntervalSince1970: 1_000_000), exercises: [e])
        return (Library(exercises: [both, one], routines: [Routine(name: "Legs", exercises: [e])], workouts: [w]), both, one)
    }

    func testMovingOntoAMachineSharesItsWeightsAndKeepsLoggedSetup() {
        var (l, both, one) = lib()
        let m = Machine(name: "Test Leg Extension", from: both)
        both.machineId = m.id
        l.save(both, new: m)
        XCTAssertEqual(l.exercises[0].stack, [])
        XCTAssertEqual(l.resolved[0].stack, both.stack)

        let moved = l.resolved[1].moved(to: l.machine(m.id)!)
        XCTAssertEqual(moved.stack, both.stack)
        XCTAssertEqual(moved.settings.map(\.name), ["Seat", "Pad"])
        let touched = l.save(moved)
        XCTAssertEqual(touched.machine, m.id)
        XCTAssertTrue(touched.routines)
        XCTAssertEqual(touched.workouts, [l.workouts[0].id])
        // The single-leg seat value now sits under the machine's Seat.
        XCTAssertEqual(l.workouts[0].exercises[0][setting: seat.id], "4")
        XCTAssertEqual(l.routines[0].exercises[0][setting: seat.id], "4")
        XCTAssertEqual(l.resolved[0].settings.map(\.name), ["Seat", "Pad"])
        XCTAssertEqual(l.resolved[0].brand, "Test")
        _ = one
    }

    func testEditsGoToTheMachineAndOffKeepsACopy() {
        var (l, both, one) = lib()
        let m = Machine(name: "Test Leg Extension", from: both)
        both.machineId = m.id
        l.save(both, new: m)
        l.save(l.resolved[1].moved(to: l.machine(m.id)!))
        var edit = l.resolved[1]
        edit.stack = [10, 20, 30]
        XCTAssertEqual(l.save(edit).machine, m.id)
        XCTAssertEqual(l.resolved[0].stack, [10, 20, 30])
        // An edit that changes nothing on the machine leaves it alone.
        var renamed = l.resolved[1]
        renamed.name = "Test Leg Extension One Leg"
        XCTAssertNil(l.save(renamed).machine)

        var off = l.resolved[1]
        off.machineId = nil
        l.save(off)
        XCTAssertEqual(l.exercises[1].stack, [10, 20, 30])
        XCTAssertEqual(l.exercises[1].settings.map(\.name), ["Seat", "Pad"])
        XCTAssertEqual(l.resolved[0].stack, [10, 20, 30])
        _ = one
    }

    func testNewExerciseStartsWithTheMachinesLastSetup() {
        var (l, _, one) = lib()
        let m = Machine(name: "Test Leg Extension", from: one)
        var on = one
        on.machineId = m.id
        l.save(on, new: m)
        let fresh = Exercise(name: "Test Leg Extension Pause").moved(to: l.machine(m.id)!)
        XCTAssertNil(l.save(fresh).machine)
        let byId = Dictionary(uniqueKeysWithValues: l.resolved.map { ($0.id, $0) })
        let last = Previous.onMachine(m.id, in: l.workouts, exercises: byId)
        let e = WorkoutExercise.adding(byId[fresh.id]!, last: nil, onMachine: last)
        XCTAssertEqual(e[setting: one.settings[0].id], "4")
        // Its own history comes first: nothing from the machine when it was done before.
        var routine = Routine(name: "Pause", exercises: [WorkoutExercise(exerciseId: fresh.id)])
        XCTAssertEqual(Workout.from(routine, exercises: byId, history: l.workouts, gymId: nil).exercises[0][setting: one.settings[0].id], "4")
        routine.exercises = [WorkoutExercise(exerciseId: one.id)]
        XCTAssertEqual(Workout.from(routine, exercises: byId, history: l.workouts, gymId: nil).exercises[0][setting: one.settings[0].id], "")
    }

    func testMachinesSyncAndStore() throws {
        var (l, both, _) = lib()
        let m = Machine(name: "Test Leg Extension", from: both)
        both.machineId = m.id
        l.save(both, new: m)
        var copy = Library()
        for r in Sync.records(l).values {
            Sync.apply(try FileStore.decoder.decode(SyncRecord.self, from: FileStore.encoder.encode(r)), to: &copy)
        }
        XCTAssertEqual(copy.machines, l.machines)
        XCTAssertTrue(SyncRecord(kind: .machine, id: m.id.uuidString).deleted)

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileStore(root: dir)
        try store.save(l)
        XCTAssertEqual(try store.load().resolved, l.resolved)
    }
}
