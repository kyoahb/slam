import Foundation

/// What syncs between the phone and the Slam server, one record at a time.
public enum SyncKind: String, Codable, CaseIterable, Sendable {
    case exercise, machine, folder, routine, gym, workout, settings
    /// The workout in progress: the phone sends it, nothing else changes it.
    case active
}

/// One record as it travels. No value means it was deleted.
public struct SyncRecord: Codable, Hashable, Sendable {
    public var kind: SyncKind
    /// The record's UUID, or the kind's name for the one settings and the one workout in progress.
    public var id: String
    /// When it was last edited, wherever that happened. The newer edit wins.
    public var updated: Date
    /// The server's order of changes.
    public var seq: Int
    public var exercise: Exercise?
    public var machine: Machine?
    public var folder: Folder?
    public var routine: Routine?
    public var gym: Gym?
    public var workout: Workout?
    public var settings: Settings?

    public init(kind: SyncKind, id: String, updated: Date = Date(), seq: Int = 0) {
        self.kind = kind
        self.id = id
        self.updated = updated
        self.seq = seq
    }

    public var key: String { kind.rawValue + "/" + id }
    public var deleted: Bool { exercise == nil && machine == nil && folder == nil && routine == nil && gym == nil && workout == nil && settings == nil }

    /// The same record, deleted.
    public func tombstone(at date: Date = Date()) -> SyncRecord { SyncRecord(kind: kind, id: id, updated: date, seq: seq) }

    /// A short fingerprint of the value alone, to tell whether it changed since it last synced.
    public var fingerprint: UInt64 {
        var copy = self
        copy.updated = Date(timeIntervalSince1970: 0)
        copy.seq = 0
        let data = (try? FileStore.encoder.encode(copy)) ?? Data()
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        return hash
    }
}

public struct SyncRequest: Codable, Sendable {
    /// The last `cursor` the phone got back.
    public var cursor: Int
    public var changes: [SyncRecord]

    public init(cursor: Int, changes: [SyncRecord]) {
        self.cursor = cursor
        self.changes = changes
    }
}

public struct SyncResponse: Codable, Sendable {
    public var cursor: Int
    /// What changed on the server since the request's cursor.
    public var changes: [SyncRecord]

    public init(cursor: Int, changes: [SyncRecord]) {
        self.cursor = cursor
        self.changes = changes
    }
}

/// The phone's side: what it last agreed on with the server.
public struct SyncState: Codable, Sendable {
    public var cursor = 0
    /// Fingerprints of the records as last synced, by key.
    public var synced: [String: UInt64] = [:]
    public var lastSync: Date?

    public init() {}
}

public enum Sync {
    public static let settingsId = "settings"
    public static let activeId = "active"

    /// Every record in a library, by key.
    public static func records(_ lib: Library) -> [String: SyncRecord] {
        var out: [String: SyncRecord] = [:]
        func add(_ r: SyncRecord) { out[r.key] = r }
        for e in lib.exercises { var r = SyncRecord(kind: .exercise, id: e.id.uuidString); r.exercise = e; add(r) }
        for m in lib.machines { var r = SyncRecord(kind: .machine, id: m.id.uuidString); r.machine = m; add(r) }
        for f in lib.folders { var r = SyncRecord(kind: .folder, id: f.id.uuidString); r.folder = f; add(r) }
        for x in lib.routines { var r = SyncRecord(kind: .routine, id: x.id.uuidString); r.routine = x; add(r) }
        for g in lib.gyms { var r = SyncRecord(kind: .gym, id: g.id.uuidString); r.gym = g; add(r) }
        for w in lib.workouts { var r = SyncRecord(kind: .workout, id: w.id.uuidString); r.workout = w; add(r) }
        var s = SyncRecord(kind: .settings, id: settingsId)
        s.settings = lib.settings
        add(s)
        if let w = lib.active { var r = SyncRecord(kind: .active, id: activeId); r.workout = w; add(r) }
        return out
    }

    /// Puts a record into a library, or takes it out when it was deleted. Keeps the library's order:
    /// workouts newest first, everything else where it was or at the end.
    public static func apply(_ r: SyncRecord, to lib: inout Library) {
        func put<T: Identifiable>(_ value: T?, _ list: inout [T]) where T.ID == UUID {
            let i = list.firstIndex { $0.id.uuidString == r.id }
            switch (value, i) {
            case let (v?, i?): list[i] = v
            case let (v?, nil): list.append(v)
            case let (nil, i?): list.remove(at: i)
            case (nil, nil): break
            }
        }
        switch r.kind {
        case .exercise: put(r.exercise, &lib.exercises)
        case .machine: put(r.machine, &lib.machines)
        case .folder: put(r.folder, &lib.folders)
        case .routine: put(r.routine, &lib.routines)
        case .gym: put(r.gym, &lib.gyms)
        case .workout:
            put(r.workout, &lib.workouts)
            lib.workouts.sort { $0.start > $1.start }
        case .settings: if let s = r.settings { lib.settings = s }
        case .active: lib.active = r.workout
        }
    }

    /// The phone's changes since it last synced: edited records stamped with when they were saved, and
    /// markers for the ones it deleted.
    public static func changes(_ lib: Library, _ state: SyncState, now: Date = Date(),
                               saved: (SyncRecord) -> Date?) -> [SyncRecord] {
        let local = records(lib)
        var out: [SyncRecord] = []
        for (key, r) in local where state.synced[key] != r.fingerprint {
            var r = r
            r.updated = saved(r) ?? now
            out.append(r)
        }
        for key in state.synced.keys where local[key] == nil {
            guard let r = record(key) else { continue }
            out.append(r.tombstone(at: now))
        }
        return out.sorted { $0.key < $1.key }
    }

    /// After a sync: what the phone sent now counts as synced, and the server's changes go in unless the
    /// phone sent a newer edit of the same record. Returns the server's changes that went in.
    @discardableResult
    public static func finish(_ lib: inout Library, _ state: inout SyncState, sent: [SyncRecord],
                              response: SyncResponse, now: Date = Date()) -> [SyncRecord] {
        var mine: [String: SyncRecord] = [:]
        for r in sent {
            mine[r.key] = r
            state.synced[r.key] = r.deleted ? nil : r.fingerprint
        }
        var applied: [SyncRecord] = []
        for r in response.changes where r.kind != .active {
            if let m = mine[r.key], m.updated >= r.updated { continue }
            apply(r, to: &lib)
            state.synced[r.key] = r.deleted ? nil : r.fingerprint
            applied.append(r)
        }
        state.cursor = response.cursor
        state.lastSync = now
        return applied
    }

    /// A bare record for a key, to mark it deleted.
    public static func record(_ key: String) -> SyncRecord? {
        let parts = key.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, let kind = SyncKind(rawValue: parts[0]) else { return nil }
        return SyncRecord(kind: kind, id: parts[1])
    }

    /// Photo files the library points at.
    public static func photoFiles(_ lib: Library) -> Set<String> {
        var files = Set(lib.workouts.flatMap { $0.photos.map(\.file) } + (lib.active?.photos.map(\.file) ?? []))
        for e in lib.exercises { if let p = e.photo { files.insert(p) } }
        return files
    }

    /// A photo file name the server will store: letters, digits, dots, dashes and underscores only.
    public static func safeFile(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 120 && !name.hasPrefix(".")
            && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }
    }
}

extension FileStore {
    /// When the file holding a record was last saved: the phone's edit time for that record.
    public func saved(_ r: SyncRecord) -> Date? {
        let name = switch r.kind {
        case .exercise: "exercises.json"
        case .machine: "machines.json"
        case .folder, .routine: "routines.json"
        case .gym: "gyms.json"
        case .settings: "settings.json"
        case .active: "active.json"
        case .workout: "workouts/\(r.id).json"
        }
        let url = root.appendingPathComponent(name)
        return (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    var syncFile: URL { root.appendingPathComponent("sync.json") }

    public func loadSync() -> SyncState { read(SyncState.self, "sync.json") ?? SyncState() }
    public func saveSync(_ s: SyncState) throws { try write(s, "sync.json") }
}
