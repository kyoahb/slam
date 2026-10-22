import Foundation
import Hummingbird
import HummingbirdTesting
import SlamCore
import XCTest
@testable import SlamServer

final class AgentTests: XCTestCase {
    private var dir: URL!
    private let tokens = Tokens(phone: String(repeating: "p", count: 32), read: String(repeating: "r", count: 32),
                                write: String(repeating: "w", count: 32))
    private let press = UUID()
    private let curl = UUID()
    private let gym = UUID()
    private let workout = UUID()
    private let seat = UUID()

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    /// Two invented exercises, one gym and one workout from two days ago.
    private func seeded() async throws -> Vault {
        let vault = try Vault(root: dir)
        var chest = Exercise(id: press, name: "Test Chest Press", primary: .chest)
        chest.stack = Exercise.slots(from: 5, step: 5, to: 100)
        chest.addOn = 2.5
        chest.settings = [Configurable(id: seat, name: "Seat")]
        var preacher = Exercise(id: curl, name: "Test Preacher Curl", equipment: .barbell, primary: .biceps)
        preacher.bar = 15
        let start = Date().addingTimeInterval(-2 * 86400)
        var e = WorkoutExercise(exerciseId: press)
        e[setting: seat] = "4"
        e.sets = [WorkSet(kind: .warmup, kg: 20, reps: 10, done: true),
                  WorkSet(kg: 40, reps: 8, rir: 1, done: true),
                  WorkSet(kg: 42.5, reps: 6, rir: 0, done: true)]
        let w = Workout(id: workout, title: "Push", start: start, end: start.addingTimeInterval(3600), gymId: gym, exercises: [e])
        try await vault.put(Agent.record(chest))
        try await vault.put(Agent.record(preacher))
        var g = SyncRecord(kind: .gym, id: gym.uuidString)
        g.gym = Gym(id: gym, name: "Test Gym")
        try await vault.put(g)
        try await vault.put(Agent.record(w))
        return vault
    }

    private func json(_ response: TestResponse) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(response.body.readableBytesView), options: .fragmentsAllowed)
    }

    private func body(_ s: String) -> ByteBuffer { ByteBuffer(bytes: Array(s.utf8)) }

    func testReadsShowSetsLikeThePhone() async throws {
        let vault = try await seeded()
        let app = Application(router: Routes.router(vault, tokens))
        let read: HTTPFields = [.authorization: "Bearer " + tokens.read]
        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/agent/workouts", method: .get) { XCTAssertEqual($0.status, .unauthorized) }
            try await client.execute(uri: "/v1/agent/workouts", method: .get, headers: [.authorization: "Bearer " + tokens.phone]) {
                XCTAssertEqual($0.status, .forbidden)
            }
            try await client.execute(uri: "/v1/agent/workouts?limit=5", method: .get, headers: read) { response in
                let list = try XCTUnwrap(self.json(response) as? [[String: Any]])
                XCTAssertEqual(list.count, 1)
                XCTAssertEqual(list[0]["gym"] as? String, "Test Gym")
                XCTAssertEqual(list[0]["volume_kg"] as? Double, 575)
                XCTAssertEqual(list[0]["sets"] as? Int, 3)
            }
            try await client.execute(uri: "/v1/agent/workouts/\(self.workout.uuidString.lowercased())", method: .get, headers: read) { response in
                let w = try XCTUnwrap(self.json(response) as? [String: Any])
                let entry = try XCTUnwrap((w["exercises"] as? [[String: Any]])?.first)
                XCTAssertEqual(entry["settings"] as? [String: String], ["Seat": "4"])
                let sets = try XCTUnwrap(entry["sets"] as? [[String: Any]])
                XCTAssertEqual(sets.map { $0["set"] as? String }, ["W", "1", "2"])
                XCTAssertEqual(sets[1]["text"] as? String, "40 kg × 8 (RIR 1)")
                XCTAssertEqual(sets[0]["text"] as? String, "20 kg × 10")
                XCTAssertTrue((w["start"] as? String)?.hasSuffix("Z") == false)
            }
            try await client.execute(uri: "/v1/agent/history?exercise=chest%20press", method: .get, headers: read) { response in
                let h = try XCTUnwrap(self.json(response) as? [String: Any])
                let bests = try XCTUnwrap(h["bests"] as? [String: Any])
                XCTAssertEqual(bests["heaviest"] as? String, "42.5 kg × 6")
                XCTAssertEqual((h["sessions"] as? [Any])?.count, 1)
            }
            try await client.execute(uri: "/v1/agent/history?exercise=press%20curl", method: .get, headers: read) { response in
                XCTAssertEqual(response.status, .notFound)
                XCTAssertTrue(String(buffer: response.body).contains("Test Chest Press"))
            }
            try await client.execute(uri: "/v1/agent/progress?exercise=Test%20Chest%20Press&metric=heaviest&by=week", method: .get,
                                     headers: read) { response in
                let p = try XCTUnwrap(self.json(response) as? [String: Any])
                XCTAssertEqual((p["points"] as? [[String: Any]])?.first?["value"] as? Double, 42.5)
            }
            try await client.execute(uri: "/v1/agent/weeks?weeks=2", method: .get, headers: read) { response in
                let weeks = try XCTUnwrap(self.json(response) as? [[String: Any]])
                XCTAssertEqual(weeks.reduce(0) { $0 + ($1["workouts"] as? Int ?? 0) }, 1)
                XCTAssertEqual(weeks.compactMap { ($0["sets_per_muscle"] as? [String: Int])?["chest"] }, [2])
            }
            try await client.execute(uri: "/v1/agent/records", method: .get, headers: read) { response in
                XCTAssertEqual((try self.json(response) as? [Any])?.count, 1)
            }
            try await client.execute(uri: "/v1/agent/exercises?muscle=biceps", method: .get, headers: read) { response in
                let list = try XCTUnwrap(self.json(response) as? [[String: Any]])
                XCTAssertEqual(list.map { $0["name"] as? String }, ["Test Preacher Curl"])
                XCTAssertEqual(list[0]["bar"] as? Double, 15)
            }
            try await client.execute(uri: "/v1/agent/active", method: .get, headers: read) { response in
                XCTAssertTrue(try self.json(response) is NSNull)
            }
        }
    }

    func testRoutineWriteReachesThePhone() async throws {
        let vault = try await seeded()
        let app = Application(router: Routes.router(vault, tokens))
        let cursor = await vault.seq
        let routine = """
        {"name": "Push A", "folder": "Test Split", "exercises": [
          {"exercise": "test chest press", "settings": {"seat": "5"},
           "sets": [{"kind": "warmup", "kg": 20, "reps": 10}, {"kg": 42.5, "reps": 8, "rir": 1}]}]}
        """
        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/agent/routines", method: .post, headers: [.authorization: "Bearer " + tokens.read],
                                     body: self.body(routine)) { XCTAssertEqual($0.status, .forbidden) }
            try await client.execute(uri: "/v1/agent/routines", method: .post, headers: [.authorization: "Bearer " + tokens.write],
                                     body: self.body(routine)) { response in
                XCTAssertEqual(response.status, .ok)
                let r = try XCTUnwrap(self.json(response) as? [String: Any])
                XCTAssertEqual(r["folder"] as? String, "Test Split")
                let sets = try XCTUnwrap((r["exercises"] as? [[String: Any]])?.first?["sets"] as? [[String: Any]])
                XCTAssertEqual(sets.map { $0["text"] as? String }, ["20 kg × 10", "42.5 kg × 8 (RIR 1)"])
            }
            try await client.execute(uri: "/v1/agent/routines", method: .post, headers: [.authorization: "Bearer " + tokens.write],
                                     body: self.body(#"{"name": "X", "exercises": [{"exercise": "Test Chest Press", "settings": {"Pad": "1"}}]}"#)) {
                XCTAssertEqual($0.status, .badRequest)
                XCTAssertTrue(String(buffer: $0.body).contains("It has: Seat"))
            }
        }
        // The phone's next sync brings the folder and the routine.
        let back = try await vault.sync(SyncRequest(cursor: cursor, changes: []))
        XCTAssertEqual(Set(back.changes.map(\.kind)), [.folder, .routine])
        let r = try XCTUnwrap(back.changes.first { $0.kind == .routine }?.routine)
        XCTAssertEqual(r.exercises.first?[setting: seat], "5")
        XCTAssertEqual(r.exercises.first?.sets.map(\.done), [false, false])
    }

    func testLoggedWorkoutsChangeOnlyWhenConfirmed() async throws {
        let vault = try await seeded()
        let app = Application(router: Routes.router(vault, tokens))
        let write: HTTPFields = [.authorization: "Bearer " + tokens.write]
        let uri = "/v1/agent/workouts/\(workout.uuidString)"
        try await app.test(.router) { client in
            try await client.execute(uri: uri, method: .post, headers: write, body: self.body(#"{"title": "Chest"}"#)) {
                XCTAssertEqual($0.status, .conflict)
            }
            try await client.execute(uri: uri, method: .post, headers: write, body: self.body(#"{"title": "Chest", "confirm": true}"#)) {
                XCTAssertEqual(try (self.json($0) as? [String: Any])?["title"] as? String, "Chest")
            }
            // A forgotten workout an hour after the logged one needs confirming too.
            let near = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-2 * 86400 + 3600))
            let forgot = """
            {"title": "Arms", "start": "\(near)", "minutes": 40, "gym": "test gym",
             "exercises": [{"exercise": "Test Preacher Curl", "sets": [{"kg": 35, "reps": 10, "rir": 2}]}]}
            """
            try await client.execute(uri: "/v1/agent/workouts", method: .post, headers: write, body: self.body(forgot)) {
                XCTAssertEqual($0.status, .conflict)
            }
            try await client.execute(uri: "/v1/agent/workouts", method: .post, headers: write,
                                     body: self.body(forgot.replacingOccurrences(of: "\"Arms\",", with: "\"Arms\", \"confirm\": true,"))) { response in
                let w = try XCTUnwrap(self.json(response) as? [String: Any])
                let set = try XCTUnwrap(((w["exercises"] as? [[String: Any]])?.first?["sets"] as? [[String: Any]])?.first)
                XCTAssertEqual(set["text"] as? String, "35 kg (10 a side) × 10 (RIR 2)")
                XCTAssertEqual(set["done"] as? Bool, true)
                XCTAssertEqual(w["minutes"] as? Int, 40)
            }
            try await client.execute(uri: uri, method: .post, headers: write, body: self.body(#"{"delete": true, "confirm": true}"#)) {
                XCTAssertEqual($0.status, .ok)
            }
        }
        let lib = await vault.library()
        XCTAssertEqual(lib.workouts.map(\.title), ["Arms"])
        XCTAssertEqual(lib.workouts.first?.exercises.first?.sets.first?.load?.plates, [10])
    }

    func testExerciseChanges() async throws {
        let vault = try await seeded()
        let app = Application(router: Routes.router(vault, tokens))
        let write: HTTPFields = [.authorization: "Bearer " + tokens.write]
        try await app.test(.router) { client in
            let change = """
            {"id": "\(self.press.uuidString)", "stack_range": {"from": 4.5, "step": 4.5, "to": 90}, "add_on": 0,
             "settings": [{"name": "seat"}, {"name": "Back Pad", "per_workout": true}]}
            """
            try await client.execute(uri: "/v1/agent/exercises", method: .post, headers: write, body: self.body(change)) { response in
                let e = try XCTUnwrap(self.json(response) as? [String: Any])
                XCTAssertNil(e["add_on"])
                XCTAssertEqual((e["stack"] as? [Double])?.prefix(2), [4.5, 9])
                XCTAssertEqual(e["settings"] as? [String], ["seat", "Back Pad (each workout)"])
            }
            try await client.execute(uri: "/v1/agent/exercises", method: .post, headers: write,
                                     body: self.body(#"{"name": "Test Chest Press"}"#)) { XCTAssertEqual($0.status, .conflict) }
            try await client.execute(uri: "/v1/agent/exercises", method: .post, headers: write,
                                     body: self.body(#"{"name": "Test Row", "equipment": "cable", "primary": "upperBack"}"#)) {
                XCTAssertEqual(try (self.json($0) as? [String: Any])?["equipment"] as? String, "cable")
            }
        }
        let lib = await vault.library()
        let chest = try XCTUnwrap(lib.exercises.first { $0.id == press })
        // The renamed setting keeps its id, so values already logged stay with it.
        XCTAssertEqual(chest.settings.first?.id, seat)
        XCTAssertEqual(lib.exercises.count, 3)
    }

    func testMachinesShareWeightsAndSetup() async throws {
        let vault = try await seeded()
        var lib = await vault.library()
        var single = Exercise(name: "Test Chest Press Single", primary: .chest, unilateral: true)
        let back = Configurable(name: "seat")
        single.settings = [back]
        lib.exercises.append(single)
        let group = MachineGroups.Group(name: "Test Chest Press", stack: Exercise.slots(from: 5, step: 5, to: 100), addOn: 2.5,
                                        settings: ["Seat"], exercises: [press, single.id])
        let lines = try MachineGroups.apply([group], to: &lib)
        XCTAssertEqual(lines, ["Test Chest Press: 2 exercises, 20 weights, settings Seat"])
        // Running the same list again changes nothing.
        var again = lib
        _ = try MachineGroups.apply([group], to: &again)
        XCTAssertEqual(Sync.records(again).mapValues(\.fingerprint), Sync.records(lib).mapValues(\.fingerprint))
        _ = try await vault.replace(with: lib)

        let app = Application(router: Routes.router(vault, tokens))
        let write: HTTPFields = [.authorization: "Bearer " + tokens.write]
        try await app.test(.router) { client in
            let change = """
            {"id": "\(single.id.uuidString)", "stack_range": {"from": 4.5, "step": 4.5, "to": 90}}
            """
            try await client.execute(uri: "/v1/agent/exercises", method: .post, headers: write, body: self.body(change)) { response in
                let e = try XCTUnwrap(self.json(response) as? [String: Any])
                XCTAssertEqual(e["machine"] as? String, "Test Chest Press")
                XCTAssertEqual(e["same_machine"] as? [String], ["Test Chest Press"])
                XCTAssertEqual(e["settings"] as? [String], ["Seat"])
            }
        }
        let now = await vault.library()
        XCTAssertEqual(now.machines.count, 1)
        XCTAssertEqual(now.resolved.first { $0.id == press }?.stack.first, 4.5)
        XCTAssertEqual(now.exercises.first { $0.id == press }?.stack, [])
        XCTAssertEqual(now.resolved.first { $0.id == single.id }?.settings.first?.id, seat)
    }

    /// Clients send spaces as "+" (Python's httpx does); names are found whatever the word order.
    func testQueriesAsClientsSendThem() async throws {
        let vault = try await seeded()
        let app = Application(router: Routes.router(vault, tokens))
        let read: HTTPFields = [.authorization: "Bearer " + tokens.read]
        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/agent/history?exercise=Test+Chest+Press&limit=1", method: .get, headers: read) { response in
                XCTAssertEqual(response.status, .ok)
                let h = try XCTUnwrap(self.json(response) as? [String: Any])
                XCTAssertEqual((h["bests"] as? [String: Any])?["exercise"] as? String, "Test Chest Press")
            }
            try await client.execute(uri: "/v1/agent/exercises?query=press+test", method: .get, headers: read) { response in
                let list = try XCTUnwrap(self.json(response) as? [[String: Any]])
                XCTAssertEqual(list.map { $0["name"] as? String }, ["Test Chest Press"])
            }
            try await client.execute(uri: "/v1/agent/progress?exercise=chest+test&metric=heaviest", method: .get, headers: read) { response in
                XCTAssertEqual(response.status, .ok)
            }
            try await client.execute(uri: "/v1/agent/records?exercise=Test%20Preacher+Curl", method: .get, headers: read) { response in
                let list = try XCTUnwrap(self.json(response) as? [[String: Any]])
                XCTAssertEqual(list.first?["exercise"] as? String, "Test Preacher Curl")
            }
            try await client.execute(uri: "/v1/agent/workouts?start=2026-10-21T00:00:00%2B01:00", method: .get, headers: read) { response in
                XCTAssertEqual(response.status, .ok)
            }
            try await client.execute(uri: "/v1/agent/workouts?start=2026-10-21T00:00:00+01:00", method: .get, headers: read) { response in
                XCTAssertEqual(response.status, .ok)
            }
            try await client.execute(uri: "/v1/agent/workouts?start=last+week", method: .get, headers: read) { response in
                XCTAssertEqual(response.status, .badRequest)
            }
            try await client.execute(uri: "/v1/agent/workouts?start=&limit=5", method: .get, headers: read) { response in
                XCTAssertEqual(try (self.json(response) as? [Any])?.count, 1)
            }
        }
    }
}
