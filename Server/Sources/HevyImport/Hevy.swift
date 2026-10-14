import Foundation

/// The Hevy API's JSON as pulled into the raw folder, one file per page.
struct Hevy {
    struct Workout: Decodable {
        var id: String
        var title: String
        var routineId: String?
        var description: String?
        var startTime: String
        var endTime: String?
        var exercises: [Entry]

        /// The day it started on, as Hevy wrote it (yyyy-MM-dd).
        var day: String { String(startTime.prefix(10)) }
    }

    /// An exercise inside a workout or a routine.
    struct Entry: Decodable {
        var index: Int?
        var title: String
        var notes: String?
        var exerciseTemplateId: String
        var supersetId: Int?
        var sets: [Set]
    }

    struct Set: Decodable {
        var type: String
        var weightKg: Double?
        var reps: Int?
        var distanceMeters: Double?
        var durationSeconds: Int?
    }

    struct Routine: Decodable {
        var id: String
        var title: String
        var folderId: Int?
        var exercises: [Entry]
    }

    struct Folder: Decodable {
        var id: Int
        var index: Int?
        var title: String
    }

    struct Template: Decodable {
        var id: String
        var title: String
        var type: String
        var primaryMuscleGroup: String?
        var secondaryMuscleGroups: [String]?
        var equipment: String?
        var isCustom: Bool?
    }

    /// Oldest first.
    var workouts: [Workout]
    var routines: [Routine]
    var folders: [Folder]
    var templates: [String: Template]

    static func load(_ dir: URL) throws -> Hevy {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()

        func pages<T: Decodable>(_ prefix: String, _ type: T.Type) throws -> [T] {
            try files.filter { $0.hasPrefix(prefix + "_p") && $0.hasSuffix(".json") }.flatMap { name -> [T] in
                let data = try Data(contentsOf: dir.appendingPathComponent(name))
                return try d.decode(Page<T>.self, from: data).items
            }
        }

        var templates: [String: Template] = [:]
        for t in try pages("exercise_templates", Template.self) { templates[t.id] = t }
        // Templates fetched one by one, because the list missed them.
        for name in files where name.hasPrefix("exercise_template_") && name.hasSuffix(".json") {
            if let t = try? d.decode(Template.self, from: Data(contentsOf: dir.appendingPathComponent(name))) {
                templates[t.id] = t
            }
        }
        // Pages overlap when the list shifts during a pull: each id once.
        func once<T, K: Hashable>(_ xs: [T], _ id: (T) -> K) -> [T] {
            var seen = Swift.Set<K>()
            return xs.filter { seen.insert(id($0)).inserted }
        }
        return Hevy(workouts: once(try pages("workouts", Workout.self), \.id).sorted { $0.startTime < $1.startTime },
                    routines: once(try pages("routines", Routine.self), \.id),
                    folders: once(try pages("routine_folders", Folder.self), \.id).sorted { ($0.index ?? 0) < ($1.index ?? 0) },
                    templates: templates)
    }

    /// One page: the list sits under a key named after the kind ("workouts", "routine_folders").
    private struct Page<T: Decodable>: Decodable {
        var items: [T]

        struct Key: CodingKey {
            var stringValue: String
            var intValue: Int? { nil }
            init(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { nil }
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Key.self)
            guard let k = c.allKeys.first(where: { $0.stringValue != "page" && $0.stringValue != "pageCount" }) else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "page without a list"))
            }
            items = try c.decode([T].self, forKey: k)
        }
    }

    static func date(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }
}
