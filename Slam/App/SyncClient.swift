import BackgroundTasks
import Foundation
import Security
import SlamCore

/// The Slam server on your PC: its address and the phone's token. Set once from the setup link
/// (`slam://sync?url=…&token=…`, a QR code shown on the PC); the token stays in the Keychain.
struct SyncConfig: Equatable {
    var url: URL
    var token: String

    private static let urlKey = "syncURL"
    private static let service = "com.kyoahb.slam.sync"

    static func load() -> SyncConfig? {
        guard let s = UserDefaults.standard.string(forKey: urlKey), let url = URL(string: s), let token = Keychain.read(service)
        else { return nil }
        return SyncConfig(url: url, token: token)
    }

    func save() {
        UserDefaults.standard.set(url.absoluteString, forKey: Self.urlKey)
        Keychain.write(token, Self.service)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: urlKey)
        Keychain.write(nil, service)
    }

    /// Reads a setup link. Only https, so the token never travels in the clear.
    init?(link: URL) {
        guard link.scheme == "slam", link.host() == "sync",
              let items = URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems,
              let s = items.first(where: { $0.name == "url" })?.value, let url = URL(string: s), url.scheme == "https",
              let token = items.first(where: { $0.name == "token" })?.value, token.count >= 32
        else { return nil }
        self.url = url
        self.token = token
    }

    init(url: URL, token: String) {
        self.url = url
        self.token = token
    }
}

/// What Settings shows about syncing.
struct SyncStatus {
    var last: Date?
    var error: String?
    var running = false
    var again = false
}

extension AppModel {
    nonisolated static let refreshTask = "com.kyoahb.slam.sync"

    /// Everything the phone has, as it would sync.
    var library: Library {
        Library(exercises: exercises, folders: folders, routines: routines, gyms: gyms, settings: settings,
                workouts: workouts, active: editor?.workout)
    }

    /// A sync a few seconds after the last change.
    func syncSoon() {
        guard syncConfig != nil else { return }
        syncDelay?.cancel()
        syncDelay = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            await syncNow()
        }
    }

    func syncNow() async {
        guard let config = syncConfig else { return }
        guard !syncStatus.running else {
            // Changes made while a sync is out go in a second one.
            syncStatus.again = true
            return
        }
        syncStatus.running = true
        defer {
            syncStatus.running = false
            if syncStatus.again {
                syncStatus.again = false
                syncSoon()
            }
        }
        do {
            var state = store.loadSync()
            if state.cursor == 0 && state.synced.isEmpty {
                // First sync on this phone: take the server's copy first, so a new install cannot overwrite it.
                try await exchange(config, &state, send: false)
            }
            try await exchange(config, &state, send: true)
            try store.saveSync(state)
            try await syncPhotos(config)
            syncStatus.last = state.lastSync
            syncStatus.error = nil
        } catch {
            syncStatus.error = (error as? SyncError)?.description ?? error.localizedDescription
        }
    }

    /// One request: the phone's changes up, the server's down. A record edited here while the request was
    /// out keeps the edit; it goes up next time.
    private func exchange(_ config: SyncConfig, _ state: inout SyncState, send: Bool) async throws {
        var snapshot = library
        let before = Sync.records(snapshot)
        let sent = send ? Sync.changes(snapshot, state) { store.saved($0) } : []
        let response: SyncResponse = try await call(config, "v1/sync", body: SyncRequest(cursor: state.cursor, changes: sent))
        let applied = Sync.finish(&snapshot, &state, sent: sent, response: response)
        guard !applied.isEmpty else { return }
        let now = Sync.records(library)
        adopt(applied.filter { now[$0.key]?.fingerprint == before[$0.key]?.fingerprint })
    }

    /// Puts the server's changes into the app and onto disk.
    private func adopt(_ changes: [SyncRecord]) {
        guard !changes.isEmpty else { return }
        var lib = library
        for r in changes { Sync.apply(r, to: &lib) }
        let kinds = Set(changes.map(\.kind))
        if kinds.contains(.exercise) {
            exercises = lib.exercises
            reindex()
            try? store.saveExercises(exercises)
        }
        if kinds.contains(.folder) || kinds.contains(.routine) {
            folders = lib.folders
            routines = lib.routines
            try? store.saveRoutines(folders, routines)
        }
        if kinds.contains(.gym) {
            gyms = lib.gyms
            try? store.saveGyms(gyms)
        }
        if kinds.contains(.settings), settings != lib.settings {
            settings = lib.settings
            try? store.saveSettings(settings)
        }
        if kinds.contains(.workout) {
            for r in changes where r.kind == .workout {
                if let w = r.workout {
                    try? store.save(workout: w)
                } else if let id = UUID(uuidString: r.id) {
                    try? store.delete(workout: id)
                }
            }
            workouts = lib.workouts
        }
        if kinds.contains(.exercise) || kinds.contains(.workout) { recomputeRecords() }
    }

    /// Photos the server lacks go up; ones this phone lacks come down.
    private func syncPhotos(_ config: SyncConfig) async throws {
        let fm = FileManager.default
        let files = Sync.photoFiles(library)
        let have = files.filter { fm.fileExists(atPath: store.photosDir.appendingPathComponent($0).path) }
        let missing: [String] = try await call(config, "v1/photos/missing", body: have.sorted())
        for f in missing where Sync.safeFile(f) {
            let data = try Data(contentsOf: store.photosDir.appendingPathComponent(f))
            _ = try await send(config, "v1/photos/\(f)", method: "PUT", body: data, type: "image/jpeg")
        }
        try fm.createDirectory(at: store.photosDir, withIntermediateDirectories: true)
        for f in files.subtracting(have).sorted() where Sync.safeFile(f) {
            guard let data = try? await send(config, "v1/photos/\(f)", method: "GET") else { continue }
            try data.write(to: store.photosDir.appendingPathComponent(f), options: .atomic)
        }
    }

    private func call<Body: Encodable, Reply: Decodable>(_ config: SyncConfig, _ path: String, body: Body) async throws -> Reply {
        let data = try await send(config, path, method: "POST", body: FileStore.encoder.encode(body), type: "application/json")
        return try FileStore.decoder.decode(Reply.self, from: data)
    }

    private func send(_ config: SyncConfig, _ path: String, method: String, body: Data? = nil, type: String? = nil) async throws -> Data {
        var request = URLRequest(url: config.url.appendingPathComponent(path), timeoutInterval: 30)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer " + config.token, forHTTPHeaderField: "Authorization")
        if let type { request.setValue(type, forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw SyncError.status(status) }
        return data
    }

    /// Takes a setup link and syncs straight away.
    func setUpSync(_ link: URL) -> Bool {
        guard !demo, let config = SyncConfig(link: link) else { return false }
        if syncConfig?.url != config.url {
            // A different server: start from scratch with it.
            try? store.saveSync(SyncState())
        }
        config.save()
        syncConfig = config
        syncStatus.error = nil
        Task { await syncNow() }
        return true
    }

    func turnOffSync() {
        SyncConfig.clear()
        syncConfig = nil
        try? store.saveSync(SyncState())
        syncStatus = SyncStatus()
    }

    /// Asks iOS for a sync while the app is away.
    func scheduleBackgroundSync() {
        guard syncConfig != nil else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTask)
        request.earliestBeginDate = Date().addingTimeInterval(30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

enum SyncError: Error, CustomStringConvertible {
    case status(Int)

    var description: String {
        switch self {
        case .status(401), .status(403): "The server did not accept this phone. Set it up again."
        case let .status(code): "The server answered \(code)."
        }
    }
}

enum Keychain {
    static func read(_ service: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String?, _ service: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        SecItemDelete(query as CFDictionary)
        guard let value else { return }
        var add = query
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}
