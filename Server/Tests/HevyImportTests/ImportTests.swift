import Foundation
import SlamCore
import XCTest
@testable import HevyImport

/// A whole import from an invented Hevy pull: two workouts at one made-up gym, one routine in one folder.
final class ImportTests: XCTestCase {
    private var root: URL!
    private var raw: URL { root.appendingPathComponent("raw") }
    private var out: URL { root.appendingPathComponent("out") }

    private let press = "TEST-PRESS", row = "TEST-ROW", curl = "TEST-CURL", crunch = "TEST-CRUNCH"

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try write("exercise_templates_p0001.json", ["page": 1, "page_count": 1, "exercise_templates": [
            template(press, "Test Chest Press", "machine", "chest"),
            template(row, "Test Bent Row (Barbell)", "barbell", "upper_back"),
            template(curl, "Test Single Arm Cable Curl", "machine", "biceps"),
            template(crunch, "Test Crunch", "none", "abdominals", type: "reps_only"),
        ]])
        try write("workouts_p0001.json", ["page": 1, "page_count": 1, "workouts": [
            workout("W2", "Push at Test Gym", "2025-02-10T08:00:00Z", [
                entry(press, "Test Chest Press", "105 + 2.5 (10 5 2.5)zp\n3 rir", [set("normal", 125, 8)]),
                entry(crunch, "Test Crunch", "fail", [set("normal", nil, 20)]),
            ]),
            workout("W1", "Push at Test Gym", "2025-01-10T08:00:00Z", [
                entry(press, "Test Chest Press", "100 + 2.5 (10 5)zp\n1: 3rir\n2: 2-3rir\nseat at 9\nfelt strong",
                      [set("warmup", 50, 10), set("normal", 117.5, 8), set("normal", 117.5, 7), set("dropset", 80, 6)]),
                entry(row, "Test Bent Row (Barbell)", "20 5 a side", [set("normal", 50, 5)]),
                entry(curl, "Test Single Arm Cable Curl", "9L8R\n8L6R", [set("normal", 20, 8), set("normal", 20, 7)]),
            ], routine: "R1"),
        ]])
        let routine: [String: Any] = ["id": "R1", "title": "Test Push", "folder_id": 7, "exercises": [
            entry(press, "Test Chest Press", "seat at 9", [set("normal", 117.5, 8)]),
        ]]
        // The same routine on two pages, as a list that shifted during the pull gives it.
        try write("routines_p0001.json", ["page": 1, "page_count": 2, "routines": [routine]])
        try write("routines_p0002.json", ["page": 2, "page_count": 2, "routines": [routine]])
        try write("routine_folders_p0001.json", ["page": 1, "page_count": 1, "routine_folders": [
            ["id": 7, "index": 0, "title": "Test Folder"],
        ]])
        let rules = Rules(gyms: [Rules.Gym(name: "Test Gym", text: ["test gym"], addOns: [2.5])], currentGym: "Test Gym",
                          pinWords: ["zp"])
        try JSONEncoder().encode(rules).write(to: out.appendingPathComponent("rules.json"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testImport() throws {
        try HevyImport.run(raw: raw, out: out)
        let lib = try FileStore(root: out.appendingPathComponent("library")).load()
        XCTAssertEqual(lib.workouts.count, 2)
        XCTAssertEqual(lib.exercises.count, 4)
        XCTAssertEqual(lib.routines.count, 1)
        XCTAssertEqual(lib.folders.map(\.name), ["Test Folder"])
        let gym = try XCTUnwrap(lib.gyms.first { $0.name == "Test Gym" })
        XCTAssertEqual(lib.settings.gymId, gym.id)
        XCTAssertTrue(lib.workouts.allSatisfy { $0.gymId == gym.id })

        let ex = Dictionary(uniqueKeysWithValues: lib.exercises.compactMap { e in e.hevyId.map { ($0, e) } })
        let chest = try XCTUnwrap(ex[press])
        XCTAssertEqual(chest.equipment, .machine)
        XCTAssertEqual(chest.stack, [100, 105])
        XCTAssertEqual(chest.addOn, 2.5)
        XCTAssertEqual(chest.settings.map(\.name), ["Seat"])
        XCTAssertEqual(ex[curl]?.equipment, .cable)
        XCTAssertEqual(ex[curl]?.unilateral, true)
        XCTAssertEqual(ex[row]?.equipment, .barbell)

        let first = try XCTUnwrap(lib.workouts.first { $0.hevyId == "W1" })
        XCTAssertEqual(first.routineId, lib.routines.first?.id)
        let p = first.exercises[0]
        XCTAssertEqual(p.sets.map(\.kind), [.warmup, .normal, .normal, .drop])
        XCTAssertEqual(p.sets[1].load, Load(base: 100, addOn: 2.5, plates: [10, 5]))
        XCTAssertEqual(p.sets[2].load, p.sets[1].load)
        XCTAssertNil(p.sets[3].load)
        XCTAssertEqual(p.sets.map(\.rir), [nil, 3, 3, nil])
        XCTAssertEqual(p[setting: chest.settings[0].id], "9")
        XCTAssertEqual(p.note, "felt strong")

        let r = first.exercises[1].sets[0]
        XCTAssertEqual(r.kg, 70)
        XCTAssertEqual(r.load, Load(base: 20, plates: [20, 5], sides: 2))

        let c = first.exercises[2].sets
        XCTAssertEqual(c.map(\.reps), [9, 8])
        XCTAssertEqual(c.map(\.repsR), [8, 6])
        XCTAssertEqual(first.exercises[2].note, "")

        let second = try XCTUnwrap(lib.workouts.first { $0.hevyId == "W2" })
        XCTAssertEqual(second.exercises[0].sets[0].load, Load(base: 105, addOn: 2.5, plates: [10, 5, 2.5]))
        XCTAssertEqual(second.exercises[0].sets[0].rir, 3)
        XCTAssertEqual(second.exercises[1].sets[0].rir, 0)

        XCTAssertEqual(lib.routines[0].exercises.first?.sets.first?.done, false)

        for name in ["dry-run.html", "summary.json", "import-map.json", "note-lines.json"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: out.appendingPathComponent(name).path), name)
        }
        let map = try JSONDecoder().decode(ImportMap.self, from: Data(contentsOf: out.appendingPathComponent("import-map.json")))
        XCTAssertEqual(map.exercises[press], chest.id)
        XCTAssertEqual(map.workouts["W1"], first.id)
    }

    func testOnlyTheOwnerCanRead() throws {
        try HevyImport.run(raw: raw, out: out)
        let fm = FileManager.default
        func mode(_ url: URL) throws -> Int {
            try XCTUnwrap(fm.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int)
        }
        XCTAssertEqual(try mode(out), 0o700)
        XCTAssertEqual(try mode(out.appendingPathComponent("library")), 0o700)
        XCTAssertEqual(try mode(out.appendingPathComponent("dry-run.html")), 0o600)
        XCTAssertEqual(try mode(out.appendingPathComponent("library/exercises.json")), 0o600)
    }

    func testRunTwiceKeepsEveryId() throws {
        try HevyImport.run(raw: raw, out: out)
        let a = try FileStore(root: out.appendingPathComponent("library")).load()
        let mapA = try Data(contentsOf: out.appendingPathComponent("import-map.json"))
        try HevyImport.run(raw: raw, out: out)
        let b = try FileStore(root: out.appendingPathComponent("library")).load()
        XCTAssertEqual(try Data(contentsOf: out.appendingPathComponent("import-map.json")), mapA)
        XCTAssertEqual(a.exercises, b.exercises)
        XCTAssertEqual(a.routines, b.routines)
        XCTAssertEqual(a.workouts.sorted { $0.start < $1.start }, b.workouts.sorted { $0.start < $1.start })
    }

    func testNoRulesStillImports() throws {
        try FileManager.default.removeItem(at: out.appendingPathComponent("rules.json"))
        try HevyImport.run(raw: raw, out: out)
        let lib = try FileStore(root: out.appendingPathComponent("library")).load()
        XCTAssertEqual(lib.workouts.count, 2)
        XCTAssertTrue(lib.gyms.isEmpty)
        XCTAssertNil(lib.workouts[0].gymId)
    }

    // MARK: Invented Hevy JSON

    private func write(_ name: String, _ object: Any) throws {
        try JSONSerialization.data(withJSONObject: object).write(to: raw.appendingPathComponent(name))
    }

    private func template(_ id: String, _ title: String, _ equipment: String, _ muscle: String,
                          type: String = "weight_reps") -> [String: Any] {
        ["id": id, "title": title, "type": type, "primary_muscle_group": muscle, "secondary_muscle_groups": [String](),
         "equipment": equipment, "is_custom": true]
    }

    private func workout(_ id: String, _ title: String, _ start: String, _ exercises: [[String: Any]],
                         routine: String? = nil) -> [String: Any] {
        var w: [String: Any] = ["id": id, "title": title, "description": "", "start_time": start,
                                "end_time": start.replacingOccurrences(of: "T08", with: "T09"), "exercises": exercises]
        if let routine { w["routine_id"] = routine }
        return w
    }

    private func entry(_ template: String, _ title: String, _ notes: String, _ sets: [[String: Any]]) -> [String: Any] {
        ["index": 0, "title": title, "notes": notes, "exercise_template_id": template, "sets": sets]
    }

    private func set(_ type: String, _ kg: Double?, _ reps: Int) -> [String: Any] {
        var s: [String: Any] = ["type": type, "reps": reps]
        if let kg { s["weight_kg"] = kg }
        return s
    }
}
