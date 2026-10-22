import Foundation
import SlamCore

/// The server's copy of everything: one JSON file per record under `records/<kind>/`, deleted ones kept as
/// markers so they cannot come back, and photos under `photos/`.
public actor Vault {
    public let root: URL
    private var records: [String: SyncRecord] = [:]
    public private(set) var seq = 0
    private var cached: Library?

    var recordsDir: URL { root.appendingPathComponent("records", isDirectory: true) }
    var photosDir: URL { root.appendingPathComponent("photos", isDirectory: true) }

    public init(root: URL) throws {
        self.root = root
        let fm = FileManager.default
        for kind in SyncKind.allCases {
            let dir = root.appendingPathComponent("records/\(kind.rawValue)", isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            for url in try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) where url.pathExtension == "json" {
                let r = try FileStore.decoder.decode(SyncRecord.self, from: Data(contentsOf: url))
                records[r.key] = r
                seq = max(seq, r.seq)
            }
        }
        try fm.createDirectory(at: root.appendingPathComponent("photos", isDirectory: true), withIntermediateDirectories: true)
    }

    /// The phone's round trip: everything changed here since its cursor, then its own changes taken in.
    public func sync(_ request: SyncRequest) throws -> SyncResponse {
        let out = records.values.filter { $0.seq > request.cursor && $0.kind != .active }.sorted { $0.seq < $1.seq }
        for r in request.changes { try accept(r) }
        return SyncResponse(cursor: seq, changes: out)
    }

    /// Keeps a change unless the stored record was edited later. Returns whether anything changed.
    @discardableResult
    public func accept(_ r: SyncRecord) throws -> Bool {
        guard Sync.safeFile(r.id) else { throw VaultError.badId(r.id) }
        let current = records[r.key]
        if let current, current.updated > r.updated { return false }
        if r.deleted {
            // Nothing there to delete.
            guard let current, !current.deleted else { return false }
        } else if let current, !current.deleted, current.fingerprint == r.fingerprint {
            return false
        }
        var r = r
        seq += 1
        r.seq = seq
        try FileStore.encoder.encode(r).write(to: file(r.key), options: .atomic)
        records[r.key] = r
        cached = nil
        return true
    }

    /// A change made here rather than on the phone: it counts as the newest edit.
    @discardableResult
    public func put(_ r: SyncRecord) throws -> Bool {
        var r = r
        r.updated = max(Date(), (records[r.key]?.updated ?? .distantPast).addingTimeInterval(1))
        return try accept(r)
    }

    /// Makes the server hold exactly `lib`, as edits made now. Refuses while it holds a workout `lib` lacks,
    /// so a logged workout is never lost. Returns how many records were written and deleted.
    public func replace(with lib: Library) throws -> (written: Int, deleted: Int) {
        let incoming = Sync.records(lib).filter { $0.value.kind != .active }
        let lost = records.values.filter { $0.kind == .workout && !$0.deleted && incoming[$0.key] == nil }
        guard lost.isEmpty else { throw VaultError.wouldLose(lost.count) }
        var written = 0, deleted = 0
        for r in incoming.values.sorted(by: { $0.key < $1.key }) {
            if try put(r) { written += 1 }
        }
        for r in records.values.sorted(by: { $0.key < $1.key }) where !r.deleted && r.kind != .active && incoming[r.key] == nil {
            if try put(r.tombstone()) { deleted += 1 }
        }
        return (written, deleted)
    }

    public func record(_ key: String) -> SyncRecord? {
        records[key].flatMap { $0.deleted ? nil : $0 }
    }

    /// Everything, as the phone sees it.
    public func library() -> Library {
        if let cached { return cached }
        var lib = Library()
        for r in records.values.sorted(by: { $0.seq < $1.seq }) where !r.deleted { Sync.apply(r, to: &lib) }
        cached = lib
        return lib
    }

    // MARK: Photos

    public func missingPhotos(_ files: [String]) -> [String] {
        files.filter { Sync.safeFile($0) && !FileManager.default.fileExists(atPath: photosDir.appendingPathComponent($0).path) }
    }

    public func savePhoto(_ data: Data, as name: String) throws {
        guard Sync.safeFile(name) else { throw VaultError.badId(name) }
        try data.write(to: photosDir.appendingPathComponent(name), options: .atomic)
    }

    public func photo(_ name: String) -> Data? {
        photoURL(name).flatMap { try? Data(contentsOf: $0) }
    }

    public func photoURL(_ name: String) -> URL? {
        guard Sync.safeFile(name) else { return nil }
        let url = photosDir.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Where an upload is written before it is whole; a dot name, so it is never served or listed as a photo.
    public func partialURL(_ name: String) -> URL {
        photosDir.appendingPathComponent(".\(UUID().uuidString)-\(name)")
    }

    /// Puts a whole upload in place, so a dropped connection never leaves half a video behind.
    public func finishPhoto(_ partial: URL, as name: String) throws {
        guard Sync.safeFile(name) else { throw VaultError.badId(name) }
        let dest = photosDir.appendingPathComponent(name)
        if rename(partial.path, dest.path) != 0 { throw CocoaError(.fileWriteUnknown) }
    }

    // MARK: Backups

    /// Copies everything to `<dir>/slam-<time>/` and keeps the newest `keep` copies.
    public func backup(to dir: URL, keep: Int = 30, now: Date = Date()) throws -> URL {
        let fm = FileManager.default
        let stamp = Self.stamp.string(from: now)
        let dest = dir.appendingPathComponent("slam-\(stamp)", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        try fm.copyItem(at: recordsDir, to: dest.appendingPathComponent("records"))
        // Photos and videos never change once written, so a backup links to the copy the last one made instead of
        // copying again: thirty days of backups take one copy's room. Left out: uploads still arriving.
        let photos = dest.appendingPathComponent("photos")
        try fm.createDirectory(at: photos, withIntermediateDirectories: true)
        let previous = try fm.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix("slam-") && $0 != dest.lastPathComponent }
            .sorted().last.map { dir.appendingPathComponent($0).appendingPathComponent("photos") }
        for name in try fm.contentsOfDirectory(atPath: photosDir.path) where Sync.safeFile(name) {
            let to = photos.appendingPathComponent(name)
            if let previous, (try? fm.linkItem(at: previous.appendingPathComponent(name), to: to)) != nil { continue }
            if (try? fm.linkItem(at: photosDir.appendingPathComponent(name), to: to)) != nil { continue }
            try fm.copyItem(at: photosDir.appendingPathComponent(name), to: to)
        }
        let old = try fm.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix("slam-") }.sorted().dropLast(keep)
        for name in old { try? fm.removeItem(at: dir.appendingPathComponent(name)) }
        return dest
    }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

    private func file(_ key: String) -> URL { recordsDir.appendingPathComponent(key + ".json") }
}

public enum VaultError: Error, CustomStringConvertible {
    case badId(String)
    case wouldLose(Int)

    public var description: String {
        switch self {
        case let .badId(id): "not a usable id: \(id)"
        case let .wouldLose(n): "the server holds \(n) workouts the library does not; nothing changed"
        }
    }
}
