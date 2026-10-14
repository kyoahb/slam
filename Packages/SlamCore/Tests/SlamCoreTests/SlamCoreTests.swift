import XCTest
@testable import SlamCore

final class PlateTests: XCTestCase {
    func testComposeUsesFewestPlates() {
        XCTAssertEqual(Plates.compose(10, from: Plates.standard), [10])
        XCTAssertEqual(Plates.compose(7.5, from: Plates.standard), [5, 2.5])
        XCTAssertEqual(Plates.compose(40, from: Plates.standard), [25, 15])
        XCTAssertEqual(Plates.compose(0, from: Plates.standard), [])
        XCTAssertNil(Plates.compose(1, from: Plates.standard))
    }

    func testTidyTurnsSmallPlatesIntoOne() {
        XCTAssertEqual(Plates.tidy([5, 2.5, 2.5], available: Plates.standard), [10])
        XCTAssertEqual(Plates.tidy([25, 10, 5], available: Plates.standard), [25, 15])
        XCTAssertNil(Plates.tidy([10], available: Plates.standard))
    }

    func testTidyRespectsAwkwardFit() {
        // A 25 does not fit on this pin: 20 is the biggest ever used.
        XCTAssertEqual(Plates.tidy([20, 5, 5, 10], available: Plates.standard, maxPlate: 20), [20, 20])
        XCTAssertEqual(Plates.tidy([20, 10, 10, 5], available: Plates.standard, maxPlate: 20), [20, 20, 5])
    }

    func testClosestFallsBelow() {
        XCTAssertEqual(Plates.closest(8.6, from: [1.25, 2.5, 5]).reduce(0, +), 7.5)
    }

    func testRetargetKeepsStackAndAddOn() {
        let load = Load(base: 109, addOn: 2, plates: [5, 2.5])
        XCTAssertEqual(load.total(.pinMachine), 118.5)
        let up = load.retargeted(to: 121, kind: .pinMachine, available: Plates.standard)
        XCTAssertEqual(up, Load(base: 109, addOn: 2, plates: [10]))
        let down = load.retargeted(to: 100, kind: .pinMachine, available: Plates.standard)
        XCTAssertEqual(down?.total(.pinMachine), 100)
        XCTAssertEqual(down?.plates, [])
        XCTAssertNil(load.retargeted(to: 112, kind: .pinMachine, available: Plates.standard))
    }

    func testPlateLoadedCountsBothSides() {
        let load = Load(plates: [20, 5])
        XCTAssertEqual(load.total(.plateLoaded), 50)
        XCTAssertEqual(load.retargeted(to: 60, kind: .plateLoaded, available: Plates.standard)?.plates, [25, 5])
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
        let prev = WorkSet(kg: 100, reps: 8, rir: 2, load: Load(base: 100))
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
        XCTAssertEqual(back.active?.exercises.first?.sets[1].load, Load(base: 109, addOn: 2, plates: [5, 2.5]))

        // A set written by an older version with fewer keys.
        let old = #"{"id":"7C9E6679-7425-40DE-944B-E07FC1F90AE7","kg":20,"reps":5}"#
        let set = try FileStore.decoder.decode(WorkSet.self, from: Data(old.utf8))
        XCTAssertEqual(set.kind, .normal)
        XCTAssertFalse(set.done)
    }
}

final class DemoTests: XCTestCase {
    func testDemoHistoryHasRecordsAndWeeks() {
        let lib = Demo.library()
        let byId = Dictionary(uniqueKeysWithValues: lib.exercises.map { ($0.id, $0) })
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
        let byId = Dictionary(uniqueKeysWithValues: lib.exercises.map { ($0.id, $0) })
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
