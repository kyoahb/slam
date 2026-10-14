import Foundation

public enum SetKind: String, Codable, CaseIterable, Sendable {
    case warmup, normal, drop
}

public enum ExerciseType: String, Codable, CaseIterable, Sendable {
    case weightReps, repsOnly, bodyweightReps, assistedBodyweight, duration, weightDuration, distanceDuration, shortDistanceWeight

    public var title: String {
        switch self {
        case .weightReps: "Weight & Reps"
        case .repsOnly: "Reps Only"
        case .bodyweightReps: "Weighted Bodyweight"
        case .assistedBodyweight: "Assisted Bodyweight"
        case .duration: "Duration"
        case .weightDuration: "Weight & Duration"
        case .distanceDuration: "Distance & Duration"
        case .shortDistanceWeight: "Weight & Distance"
        }
    }

    public var hasKg: Bool {
        switch self {
        case .weightReps, .bodyweightReps, .assistedBodyweight, .weightDuration, .shortDistanceWeight: true
        default: false
        }
    }

    public var hasReps: Bool {
        switch self {
        case .weightReps, .repsOnly, .bodyweightReps, .assistedBodyweight: true
        default: false
        }
    }

    public var hasTime: Bool {
        switch self {
        case .duration, .weightDuration, .distanceDuration: true
        default: false
        }
    }

    public var hasDistance: Bool { self == .distanceDuration || self == .shortDistanceWeight }
}

public enum Equipment: String, Codable, CaseIterable, Sendable {
    case none, barbell, dumbbell, kettlebell, machine, plate, cable, band, suspension, cardio, other

    public var title: String {
        switch self {
        case .none: "None"
        case .band: "Resistance Band"
        default: rawValue.capitalized
        }
    }
}

public enum Muscle: String, Codable, CaseIterable, Sendable {
    case abdominals, abductors, adductors, biceps, calves, cardio, chest, forearms, fullBody, glutes,
         hamstrings, lats, lowerBack, neck, quadriceps, shoulders, traps, triceps, upperBack, other

    public var title: String {
        switch self {
        case .fullBody: "Full Body"
        case .lowerBack: "Lower Back"
        case .upperBack: "Upper Back"
        default: rawValue.capitalized
        }
    }
}

/// How a weight is physically made up.
public enum LoadKind: String, Codable, CaseIterable, Sendable {
    /// Just a number (dumbbells, cable stack without extras).
    case plain
    /// Selectorised stack, optional add-on weight, plates on a gym pin.
    case pinMachine
    /// Plates loaded on each side of a bar or lever.
    case plateLoaded

    public var title: String {
        switch self {
        case .plain: "Plain"
        case .pinMachine: "Pin machine"
        case .plateLoaded: "Plate loaded"
        }
    }
}

/// The parts of a set's weight: stack (or bar), add-on, and plates (on the pin, or per side).
public struct Load: Codable, Hashable, Sendable {
    public var base: Double
    public var addOn: Double
    public var plates: [Double]

    public init(base: Double = 0, addOn: Double = 0, plates: [Double] = []) {
        self.base = base
        self.addOn = addOn
        self.plates = plates
    }
}

/// A seat height, pad position, incline... A name with a number or word value.
public struct Configurable: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// Set during each workout (cardio incline) rather than per routine (seat height).
    public var perWorkout: Bool

    public init(id: UUID = UUID(), name: String, perWorkout: Bool = false) {
        self.id = id
        self.name = name
        self.perWorkout = perWorkout
    }
}

public struct Exercise: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var type: ExerciseType
    public var equipment: Equipment
    public var primary: Muscle
    public var secondary: [Muscle]
    public var unilateral: Bool
    public var load: LoadKind
    public var brand: String
    public var settings: [Configurable]
    public var photo: String?
    public var hevyId: String?

    public init(id: UUID = UUID(), name: String, type: ExerciseType = .weightReps, equipment: Equipment = .machine,
                primary: Muscle = .other, secondary: [Muscle] = [], unilateral: Bool = false, load: LoadKind = .plain,
                brand: String = "", settings: [Configurable] = [], photo: String? = nil, hevyId: String? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.equipment = equipment
        self.primary = primary
        self.secondary = secondary
        self.unilateral = unilateral
        self.load = load
        self.brand = brand
        self.settings = settings
        self.photo = photo
        self.hevyId = hevyId
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.value(.name, "")
        type = try c.value(.type, .weightReps)
        equipment = try c.value(.equipment, .other)
        primary = try c.value(.primary, .other)
        secondary = try c.value(.secondary, [])
        unilateral = try c.value(.unilateral, false)
        load = try c.value(.load, .plain)
        brand = try c.value(.brand, "")
        settings = try c.value(.settings, [])
        photo = try c.decodeIfPresent(String.self, forKey: .photo)
        hevyId = try c.decodeIfPresent(String.self, forKey: .hevyId)
    }

    public var initials: String {
        let words = name.split(whereSeparator: { $0 == " " || $0 == "-" }).prefix(2)
        return words.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}

public struct WorkSet: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var kind: SetKind
    public var kg: Double?
    /// Reps for both sides, or the left side on a unilateral exercise.
    public var reps: Int?
    public var rir: Int?
    /// Right side on a unilateral exercise.
    public var repsR: Int?
    public var rirR: Int?
    public var seconds: Int?
    public var meters: Double?
    public var load: Load?
    public var done: Bool
    public var doneAt: Date?

    public init(id: UUID = UUID(), kind: SetKind = .normal, kg: Double? = nil, reps: Int? = nil, rir: Int? = nil,
                repsR: Int? = nil, rirR: Int? = nil, seconds: Int? = nil, meters: Double? = nil, load: Load? = nil,
                done: Bool = false, doneAt: Date? = nil) {
        self.id = id
        self.kind = kind
        self.kg = kg
        self.reps = reps
        self.rir = rir
        self.repsR = repsR
        self.rirR = rirR
        self.seconds = seconds
        self.meters = meters
        self.load = load
        self.done = done
        self.doneAt = doneAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.value(.id, UUID())
        kind = try c.value(.kind, .normal)
        kg = try c.decodeIfPresent(Double.self, forKey: .kg)
        reps = try c.decodeIfPresent(Int.self, forKey: .reps)
        rir = try c.decodeIfPresent(Int.self, forKey: .rir)
        repsR = try c.decodeIfPresent(Int.self, forKey: .repsR)
        rirR = try c.decodeIfPresent(Int.self, forKey: .rirR)
        seconds = try c.decodeIfPresent(Int.self, forKey: .seconds)
        meters = try c.decodeIfPresent(Double.self, forKey: .meters)
        load = try c.decodeIfPresent(Load.self, forKey: .load)
        done = try c.value(.done, false)
        doneAt = try c.decodeIfPresent(Date.self, forKey: .doneAt)
    }

    public var isEmpty: Bool {
        kg == nil && reps == nil && repsR == nil && seconds == nil && meters == nil
    }

    /// Every value still missing is taken from `other` (last time's matching set).
    public func filled(from other: WorkSet?) -> WorkSet {
        guard let other else { return self }
        var s = self
        if s.kg == nil {
            s.kg = other.kg
            if s.load == nil { s.load = other.load }
        }
        if s.reps == nil { s.reps = other.reps }
        if s.repsR == nil { s.repsR = other.repsR }
        if s.kind != .warmup {
            if s.rir == nil { s.rir = other.rir }
            if s.rirR == nil { s.rirR = other.rirR }
        }
        if s.seconds == nil { s.seconds = other.seconds }
        if s.meters == nil { s.meters = other.meters }
        return s
    }

    /// A fresh, unfinished set of the same kind and values.
    public var copy: WorkSet {
        var s = self
        s.id = UUID()
        s.done = false
        s.doneAt = nil
        return s
    }
}

/// One exercise inside a routine or a workout.
/// In a routine `note` is the long-term note; in a workout it is that day's short note.
public struct WorkoutExercise: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var exerciseId: UUID
    public var note: String
    /// Configurable values keyed by `Configurable.id.uuidString`.
    public var settings: [String: String]
    public var sets: [WorkSet]
    public var supersetId: Int?

    public init(id: UUID = UUID(), exerciseId: UUID, note: String = "", settings: [String: String] = [:],
                sets: [WorkSet] = [], supersetId: Int? = nil) {
        self.id = id
        self.exerciseId = exerciseId
        self.note = note
        self.settings = settings
        self.sets = sets
        self.supersetId = supersetId
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.value(.id, UUID())
        exerciseId = try c.decode(UUID.self, forKey: .exerciseId)
        note = try c.value(.note, "")
        settings = try c.value(.settings, [:])
        sets = try c.value(.sets, [])
        supersetId = try c.decodeIfPresent(Int.self, forKey: .supersetId)
    }

    public subscript(setting id: UUID) -> String {
        get { settings[id.uuidString] ?? "" }
        set { settings[id.uuidString] = newValue.isEmpty ? nil : newValue }
    }
}

public struct Photo: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var file: String
    public var addedAt: Date

    public init(id: UUID = UUID(), file: String, addedAt: Date = Date()) {
        self.id = id
        self.file = file
        self.addedAt = addedAt
    }
}

public struct Workout: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var start: Date
    public var end: Date?
    public var notes: String
    public var gymId: UUID?
    public var routineId: UUID?
    public var exercises: [WorkoutExercise]
    public var photos: [Photo]
    public var hevyId: String?

    public init(id: UUID = UUID(), title: String = "", start: Date = Date(), end: Date? = nil, notes: String = "",
                gymId: UUID? = nil, routineId: UUID? = nil, exercises: [WorkoutExercise] = [], photos: [Photo] = [],
                hevyId: String? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.notes = notes
        self.gymId = gymId
        self.routineId = routineId
        self.exercises = exercises
        self.photos = photos
        self.hevyId = hevyId
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.value(.title, "")
        start = try c.decode(Date.self, forKey: .start)
        end = try c.decodeIfPresent(Date.self, forKey: .end)
        notes = try c.value(.notes, "")
        gymId = try c.decodeIfPresent(UUID.self, forKey: .gymId)
        routineId = try c.decodeIfPresent(UUID.self, forKey: .routineId)
        exercises = try c.value(.exercises, [])
        photos = try c.value(.photos, [])
        hevyId = try c.decodeIfPresent(String.self, forKey: .hevyId)
    }

    public var duration: TimeInterval { (end ?? Date()).timeIntervalSince(start) }
}

public struct Folder: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String

    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

public struct Routine: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var folderId: UUID?
    public var exercises: [WorkoutExercise]
    public var hevyId: String?

    public init(id: UUID = UUID(), name: String, folderId: UUID? = nil, exercises: [WorkoutExercise] = [],
                hevyId: String? = nil) {
        self.id = id
        self.name = name
        self.folderId = folderId
        self.exercises = exercises
        self.hevyId = hevyId
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.value(.name, "")
        folderId = try c.decodeIfPresent(UUID.self, forKey: .folderId)
        exercises = try c.value(.exercises, [])
        hevyId = try c.decodeIfPresent(String.self, forKey: .hevyId)
    }
}

public struct Gym: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String

    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

public struct Settings: Codable, Hashable, Sendable {
    public var restSeconds: Int
    public var warmupRestSeconds: Int
    /// Gym new workouts are logged at.
    public var gymId: UUID?
    /// Plate sizes on hand for pins and bars.
    public var plates: [Double]

    public init(restSeconds: Int = 120, warmupRestSeconds: Int = 60, gymId: UUID? = nil, plates: [Double] = Plates.standard) {
        self.restSeconds = restSeconds
        self.warmupRestSeconds = warmupRestSeconds
        self.gymId = gymId
        self.plates = plates
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        restSeconds = try c.value(.restSeconds, 120)
        warmupRestSeconds = try c.value(.warmupRestSeconds, 60)
        gymId = try c.decodeIfPresent(UUID.self, forKey: .gymId)
        plates = try c.value(.plates, Plates.standard)
    }
}

extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, _ fallback: @autoclosure () -> T) throws -> T {
        try decodeIfPresent(T.self, forKey: key) ?? fallback()
    }
}
