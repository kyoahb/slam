import Foundation
import SlamCore
import XCTest
@testable import SlamServer

/// Phones and a model working on one vault, through the same steps the app takes.
final class RoundTripTests: XCTestCase {
    private struct Phone {
        var lib = Library()
        var state = SyncState()

        mutating func sync(_ vault: Vault, at seconds: TimeInterval) async throws {
            let now = Date(timeIntervalSince1970: seconds)
            if state.cursor == 0 && state.synced.isEmpty {
                let first = try await vault.sync(SyncRequest(cursor: 0, changes: []))
                Sync.finish(&lib, &state, sent: [], response: first, now: now)
            }
            let sent = Sync.changes(lib, state, now: now) { _ in now }
            let response = try await vault.sync(SyncRequest(cursor: state.cursor, changes: sent))
            Sync.finish(&lib, &state, sent: sent, response: response, now: now)
        }
    }

    func testTwoPhonesAndAModel() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let vault = try Vault(root: dir)

        var a = Phone()
        let press = Exercise(name: "Leg Press")
        a.lib.exercises = [press]
        a.lib.settings.restSeconds = 90
        a.lib.workouts = [Workout(title: "Legs", start: Date(timeIntervalSince1970: 500), exercises: [WorkoutExercise(exerciseId: press.id)])]
        a.lib.active = Workout(title: "Now")
        try await a.sync(vault, at: 1000)

        // A new phone takes everything, and its default settings do not win.
        var b = Phone()
        try await b.sync(vault, at: 1100)
        XCTAssertEqual(b.lib.exercises, a.lib.exercises)
        XCTAssertEqual(b.lib.workouts, a.lib.workouts)
        XCTAssertEqual(b.lib.settings.restSeconds, 90)
        XCTAssertNil(b.lib.active)

        // A model adds a routine; phone B deletes the workout.
        var r = SyncRecord(kind: .routine, id: UUID().uuidString)
        r.routine = Routine(id: UUID(uuidString: r.id)!, name: "Legs", exercises: [WorkoutExercise(exerciseId: press.id)])
        try await vault.put(r)
        b.lib.workouts = []
        try await b.sync(vault, at: 1200)
        try await a.sync(vault, at: 1300)
        XCTAssertEqual(a.lib.routines.map(\.name), ["Legs"])
        XCTAssertTrue(a.lib.workouts.isEmpty)
        XCTAssertTrue(Sync.changes(a.lib, a.state) { _ in nil }.isEmpty)
        let lib = await vault.library()
        XCTAssertEqual(lib.active?.title, "Now")
        XCTAssertTrue(lib.workouts.isEmpty)
    }
}
