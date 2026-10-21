import Foundation

/// Everything Slam keeps.
public struct Library: Sendable {
    public var exercises: [Exercise] = []
    public var machines: [Machine] = []
    public var folders: [Folder] = []
    public var routines: [Routine] = []
    public var gyms: [Gym] = []
    public var settings = Settings()
    /// Newest first.
    public var workouts: [Workout] = []
    /// The workout in progress, if any.
    public var active: Workout?

    public init(exercises: [Exercise] = [], machines: [Machine] = [], folders: [Folder] = [], routines: [Routine] = [],
                gyms: [Gym] = [], settings: Settings = Settings(), workouts: [Workout] = [], active: Workout? = nil) {
        self.exercises = exercises
        self.machines = machines
        self.folders = folders
        self.routines = routines
        self.gyms = gyms
        self.settings = settings
        self.workouts = workouts
        self.active = active
    }
}

/// Plain JSON files: one per finished workout, one each for the rest.
public struct FileStore: Sendable {
    public let root: URL

    public init(root: URL) { self.root = root }

    var workoutsDir: URL { root.appendingPathComponent("workouts", isDirectory: true) }
    public var photosDir: URL { root.appendingPathComponent("photos", isDirectory: true) }

    struct RoutineFile: Codable {
        var folders: [Folder]
        var routines: [Routine]
    }

    public func load() throws -> Library {
        try prepare()
        var lib = Library()
        lib.exercises = read([Exercise].self, "exercises.json") ?? []
        lib.machines = read([Machine].self, "machines.json") ?? []
        if let r = read(RoutineFile.self, "routines.json") {
            lib.folders = r.folders
            lib.routines = r.routines
        }
        lib.gyms = read([Gym].self, "gyms.json") ?? []
        lib.settings = read(Settings.self, "settings.json") ?? Settings()
        lib.active = read(Workout.self, "active.json")
        let files = (try? FileManager.default.contentsOfDirectory(at: workoutsDir, includingPropertiesForKeys: nil)) ?? []
        lib.workouts = files.filter { $0.pathExtension == "json" }
            .compactMap { try? Self.decoder.decode(Workout.self, from: Data(contentsOf: $0)) }
            .sorted { $0.start > $1.start }
        return lib
    }

    public func save(_ lib: Library) throws {
        try saveExercises(lib.exercises)
        try saveMachines(lib.machines)
        try saveRoutines(lib.folders, lib.routines)
        try saveGyms(lib.gyms)
        try saveSettings(lib.settings)
        for w in lib.workouts { try save(workout: w) }
        try saveActive(lib.active)
    }

    public func saveExercises(_ v: [Exercise]) throws { try write(v, "exercises.json") }
    public func saveMachines(_ v: [Machine]) throws { try write(v, "machines.json") }
    public func saveRoutines(_ folders: [Folder], _ routines: [Routine]) throws {
        try write(RoutineFile(folders: folders, routines: routines), "routines.json")
    }
    public func saveGyms(_ v: [Gym]) throws { try write(v, "gyms.json") }
    public func saveSettings(_ v: Settings) throws { try write(v, "settings.json") }

    public func save(workout: Workout) throws {
        try prepare()
        try Self.encoder.encode(workout).write(to: workoutsDir.appendingPathComponent("\(workout.id.uuidString).json"),
                                                options: .atomic)
    }

    public func delete(workout id: UUID) throws {
        let url = workoutsDir.appendingPathComponent("\(id.uuidString).json")
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    public func saveActive(_ w: Workout?) throws {
        let url = root.appendingPathComponent("active.json")
        if let w {
            try Self.encoder.encode(w).write(to: url, options: .atomic)
        } else if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// Deletes everything kept here except what sync remembers, so the deletions can still reach the server.
    public func wipe() throws {
        let fm = FileManager.default
        for name in ["exercises.json", "machines.json", "routines.json", "gyms.json", "settings.json", "active.json", "workouts", "photos"] {
            let url = root.appendingPathComponent(name)
            if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
        }
        try prepare()
    }

    /// One file with everything, for backups and for Cycler.
    public func export(_ lib: Library) throws -> Data {
        struct Export: Codable {
            var exercises: [Exercise]
            var machines: [Machine]
            var folders: [Folder]
            var routines: [Routine]
            var gyms: [Gym]
            var settings: Settings
            var workouts: [Workout]
        }
        return try Self.encoder.encode(Export(exercises: lib.exercises, machines: lib.machines, folders: lib.folders, routines: lib.routines,
                                              gyms: lib.gyms, settings: lib.settings, workouts: lib.workouts))
    }

    func prepare() throws {
        for dir in [root, workoutsDir, photosDir] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// A file that exists but cannot be read is copied aside first, so the next save cannot lose it.
    func read<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        let url = root.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try Self.decoder.decode(type, from: data)
        } catch {
            let aside = root.appendingPathComponent(name + ".unreadable")
            if !FileManager.default.fileExists(atPath: aside.path) { try? data.write(to: aside) }
            return nil
        }
    }

    func write<T: Encodable>(_ value: T, _ name: String) throws {
        try prepare()
        try Self.encoder.encode(value).write(to: root.appendingPathComponent(name), options: .atomic)
    }

    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys, .prettyPrinted]
        return e
    }()

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
