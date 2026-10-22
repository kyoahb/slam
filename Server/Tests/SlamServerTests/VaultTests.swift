import Foundation
import Hummingbird
import HummingbirdTesting
import SlamCore
import XCTest
@testable import SlamServer

final class VaultTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    private func routine(_ id: UUID, _ name: String, at seconds: TimeInterval) -> SyncRecord {
        var r = SyncRecord(kind: .routine, id: id.uuidString, updated: Date(timeIntervalSince1970: seconds))
        r.routine = Routine(id: id, name: name)
        return r
    }

    func testNewerEditWinsAndSurvivesRestart() async throws {
        let vault = try Vault(root: dir)
        let id = UUID()
        let first = try await vault.sync(SyncRequest(cursor: 0, changes: [routine(id, "Push", at: 2000)]))
        XCTAssertEqual(first.cursor, 1)
        XCTAssertTrue(first.changes.isEmpty)
        // Older than what is stored: refused. The same value again: nothing new.
        let older = try await vault.sync(SyncRequest(cursor: 1, changes: [routine(id, "Old", at: 1000), routine(id, "Push", at: 3000)]))
        XCTAssertEqual(older.cursor, 1)
        let edited = try await vault.put(routine(id, "Push A", at: 0))
        XCTAssertTrue(edited)

        let again = try Vault(root: dir)
        let seq = await again.seq
        XCTAssertEqual(seq, 2)
        let back = try await again.sync(SyncRequest(cursor: 1, changes: []))
        XCTAssertEqual(back.changes.map { $0.routine?.name }, ["Push A"])
        let names = await again.library().routines.map(\.name)
        XCTAssertEqual(names, ["Push A"])
    }

    func testReplaceKeepsOnlyTheLibrary() async throws {
        let vault = try Vault(root: dir)
        let old = UUID()
        _ = try await vault.sync(SyncRequest(cursor: 0, changes: [routine(old, "Check", at: 1000)]))
        var lib = Library()
        lib.exercises = [Exercise(name: "Press")]
        lib.workouts = [Workout(title: "Push")]
        let (written, deleted) = try await vault.replace(with: lib)
        XCTAssertEqual(written, 3)
        XCTAssertEqual(deleted, 1)
        let now = await vault.library()
        XCTAssertEqual(now.exercises.map(\.name), ["Press"])
        XCTAssertEqual(now.workouts.map(\.title), ["Push"])
        XCTAssertTrue(now.routines.isEmpty)

        // A workout logged since is never dropped.
        do {
            _ = try await vault.replace(with: Library())
            XCTFail("replaced away a workout")
        } catch VaultError.wouldLose(let n) {
            XCTAssertEqual(n, 1)
        }
        let after = await vault.library()
        XCTAssertEqual(after.workouts.count, 1)
    }

    func testDeleteMarkerAndActiveStayHere() async throws {
        let vault = try Vault(root: dir)
        let id = UUID()
        var active = SyncRecord(kind: .active, id: Sync.activeId, updated: Date(timeIntervalSince1970: 1000))
        active.workout = Workout(title: "Now")
        _ = try await vault.sync(SyncRequest(cursor: 0, changes: [routine(id, "Legs", at: 1000), active]))
        let gone = routine(id, "Legs", at: 2000).tombstone(at: Date(timeIntervalSince1970: 2000))
        _ = try await vault.sync(SyncRequest(cursor: 2, changes: [gone]))
        let all = try await vault.sync(SyncRequest(cursor: 0, changes: []))
        XCTAssertEqual(all.changes.count, 1)
        XCTAssertTrue(all.changes[0].deleted)
        // A stale copy of the deleted routine cannot bring it back.
        _ = try await vault.sync(SyncRequest(cursor: 3, changes: [routine(id, "Legs", at: 1500)]))
        let routines = await vault.library().routines
        XCTAssertTrue(routines.isEmpty)
        let title = await vault.library().active?.title
        XCTAssertEqual(title, "Now")
    }

    func testBackupsKeepTheNewest() async throws {
        let vault = try Vault(root: dir.appendingPathComponent("data"))
        let backups = dir.appendingPathComponent("backups")
        for day in 0..<4 {
            _ = try await vault.backup(to: backups, keep: 2, now: Date(timeIntervalSince1970: Double(day) * 86400))
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: backups.path).sorted()
        XCTAssertEqual(names, ["slam-19700103-000000", "slam-19700104-000000"])
    }

    /// Media never changes, so the next backup links to the last one's copy instead of copying again.
    func testBackupsShareUnchangedPhotos() async throws {
        let vault = try Vault(root: dir.appendingPathComponent("data"))
        try await vault.savePhoto(Data(repeating: 7, count: 1000), as: "a.mp4")
        let backups = dir.appendingPathComponent("backups")
        let one = try await vault.backup(to: backups, now: Date(timeIntervalSince1970: 0))
        let two = try await vault.backup(to: backups, now: Date(timeIntervalSince1970: 86400))
        let inode = { (u: URL) in try FileManager.default.attributesOfItem(atPath: u.appendingPathComponent("photos/a.mp4").path)[.systemFileNumber] as? Int }
        XCTAssertEqual(try inode(one), try inode(two))
        XCTAssertEqual(try Data(contentsOf: two.appendingPathComponent("photos/a.mp4")).count, 1000)
    }

    func testVideosGoUpAndComeBack() async throws {
        let vault = try Vault(root: dir)
        let tokens = Tokens(phone: String(repeating: "p", count: 32), read: String(repeating: "r", count: 32),
                            write: String(repeating: "w", count: 32))
        let app = Application(router: Routes.router(vault, tokens))
        let phone: HTTPFields = [.authorization: "Bearer " + tokens.phone]
        let video = (0..<300_000).map { UInt8($0 % 251) }
        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/photos/clip.mp4", method: .put, headers: phone, body: ByteBuffer(bytes: video)) {
                XCTAssertEqual($0.status, .noContent)
            }
            try await client.execute(uri: "/v1/photos/clip.mp4", method: .get, headers: phone) { response in
                XCTAssertEqual(response.status, .ok)
                XCTAssertEqual(response.headers[.contentType], "video/mp4")
                XCTAssertEqual(Array(response.body.readableBytesView), video)
            }
            try await client.execute(uri: "/v1/photos/missing", method: .post, headers: phone,
                                     body: ByteBuffer(bytes: Array(#"["clip.mp4","other.mov"]"#.utf8))) { response in
                XCTAssertEqual(try JSONDecoder().decode([String].self, from: Data(response.body.readableBytesView)), ["other.mov"])
            }
            try await client.execute(uri: "/v1/photos/big.jpg", method: .put, headers: phone,
                                     body: ByteBuffer(bytes: [UInt8](repeating: 1, count: Routes.maxPhoto + 1))) {
                XCTAssertEqual($0.status, .contentTooLarge)
            }
            try await client.execute(uri: "/v1/photos/big.jpg", method: .get, headers: phone) { XCTAssertEqual($0.status, .notFound) }
        }
        let left = try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("photos").path)
        XCTAssertEqual(left, ["clip.mp4"])
    }

    func testRoutesNeedTheRightToken() async throws {
        let vault = try Vault(root: dir)
        let tokens = Tokens(phone: String(repeating: "p", count: 32), read: String(repeating: "r", count: 32),
                            write: String(repeating: "w", count: 32))
        let app = Application(router: Routes.router(vault, tokens))
        let body = try FileStore.encoder.encode(SyncRequest(cursor: 0, changes: [routine(UUID(), "Pull", at: 1000)]))
        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/health", method: .get) { XCTAssertEqual($0.status, .ok) }
            try await client.execute(uri: "/v1/sync", method: .post, body: ByteBuffer(bytes: body)) {
                XCTAssertEqual($0.status, .unauthorized)
            }
            try await client.execute(uri: "/v1/sync", method: .post, headers: [.authorization: "Bearer " + tokens.read],
                                     body: ByteBuffer(bytes: body)) { XCTAssertEqual($0.status, .forbidden) }
            try await client.execute(uri: "/v1/sync", method: .post, headers: [.authorization: "Bearer " + tokens.phone],
                                     body: ByteBuffer(bytes: body)) { response in
                XCTAssertEqual(response.status, .ok)
                let back = try FileStore.decoder.decode(SyncResponse.self, from: Data(response.body.readableBytesView))
                XCTAssertEqual(back.cursor, 1)
            }
            try await client.execute(uri: "/v1/photos/x.jpg", method: .put, headers: [.authorization: "Bearer " + tokens.phone],
                                     body: ByteBuffer(bytes: [1, 2, 3])) { XCTAssertEqual($0.status, .noContent) }
            try await client.execute(uri: "/v1/photos/x.jpg", method: .get, headers: [.authorization: "Bearer " + tokens.read]) {
                XCTAssertEqual(Array($0.body.readableBytesView), [1, 2, 3])
            }
        }
    }
}
