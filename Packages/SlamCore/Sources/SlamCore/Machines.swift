import Foundation

/// A machine at the gym that several exercises are done on: a cable stack used for curls and pushdowns, a leg
/// extension used one leg at a time or both. It holds what they share, the weights and the setup (seat, pad);
/// each exercise keeps its own history and records.
public struct Machine: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var brand: String
    public var stack: [Double]
    public var addOn: Double?
    public var pin: Bool
    public var plateSides: Int
    public var bar: Double?
    public var settings: [Configurable]

    public init(id: UUID = UUID(), name: String, brand: String = "", stack: [Double] = [], addOn: Double? = nil,
                pin: Bool = false, plateSides: Int = 0, bar: Double? = nil, settings: [Configurable] = []) {
        self.id = id
        self.name = name
        self.brand = brand
        self.stack = stack
        self.addOn = addOn
        self.pin = pin
        self.plateSides = plateSides
        self.bar = bar
        self.settings = settings
    }

    /// A new machine holding what the exercise has now.
    public init(id: UUID = UUID(), name: String, from e: Exercise) {
        self.init(id: id, name: name, brand: e.brand, stack: e.stack, addOn: e.addOn, pin: e.pin, plateSides: e.plateSides,
                  bar: e.bar, settings: e.settings)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.value(.name, "")
        brand = try c.value(.brand, "")
        stack = try c.value(.stack, [])
        addOn = try c.decodeIfPresent(Double.self, forKey: .addOn)
        pin = try c.value(.pin, false)
        plateSides = try c.value(.plateSides, 0)
        bar = try c.decodeIfPresent(Double.self, forKey: .bar)
        settings = try c.value(.settings, [])
    }

    var hasWeights: Bool { !stack.isEmpty || plateSides > 0 || addOn != nil || pin || bar != nil }
}

public extension Configurable {
    /// Seat and "seat " are one setting.
    func named(_ other: String) -> Bool {
        name.trimmingCharacters(in: .whitespaces).lowercased() == other.trimmingCharacters(in: .whitespaces).lowercased()
    }
}

public extension Exercise {
    /// The exercise as used: on its machine, with the machine's weights and setup in place of its own.
    func on(_ m: Machine?) -> Exercise {
        guard let m, m.id == machineId else { return self }
        var e = self
        e.brand = m.brand
        e.stack = m.stack
        e.addOn = m.addOn
        e.pin = m.pin
        e.plateSides = m.plateSides
        e.bar = m.bar
        e.settings = m.settings
        return e
    }

    /// Moved onto a machine: the machine's weights and setup, plus its own settings the machine lacks. A machine
    /// with no weights yet takes the exercise's.
    func moved(to m: Machine) -> Exercise {
        var machine = m
        if !machine.hasWeights {
            machine.stack = stack
            machine.addOn = addOn
            machine.pin = pin
            machine.plateSides = plateSides
            machine.bar = bar
        }
        if machine.brand.isEmpty { machine.brand = brand }
        for c in settings where !machine.settings.contains(where: { $0.named(c.name) }) { machine.settings.append(c) }
        var e = self
        e.machineId = m.id
        return e.on(machine)
    }

    /// Stored on a machine: the machine holds the weights and setup.
    var bare: Exercise {
        var e = self
        e.brand = ""
        e.stack = []
        e.addOn = nil
        e.pin = false
        e.plateSides = 0
        e.bar = nil
        e.settings = []
        return e
    }
}

/// What saving an exercise changed besides the exercise, so only that is written and synced.
public struct Touched: Equatable, Sendable {
    public var machine: UUID?
    public var routines = false
    public var workouts: Set<UUID> = []
    public var active = false
    /// Setup values that moved to a setting of the same name (old id → new id), for the open editors.
    public var moved: [String: String] = [:]

    public init() {}
}

public extension Library {
    /// Every exercise as used: on a machine, with the machine's weights and setup.
    var resolved: [Exercise] {
        let byId = Dictionary(machines.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return exercises.map { e in e.on(e.machineId.flatMap { byId[$0] }) }
    }

    func machine(_ id: UUID?) -> Machine? {
        guard let id else { return nil }
        return machines.first { $0.id == id }
    }

    /// Saves an exercise as edited, with its machine's weights and setup filled in: those go to the machine, shared
    /// by every exercise on it. `new` is a machine made for it just now. When a setting went and one of the same
    /// name came (it moved onto a machine that has a Seat too), the logged values follow, in routines and workouts.
    @discardableResult
    mutating func save(_ edited: Exercise, new: Machine? = nil) -> Touched {
        var touched = Touched()
        let before = exercises.first { $0.id == edited.id }.map { $0.on(machine($0.machineId)) }
        if let new, !machines.contains(where: { $0.id == new.id }) {
            machines.append(new)
            touched.machine = new.id
        }
        var stored = edited
        if let i = machines.firstIndex(where: { $0.id == edited.machineId }) {
            var m = machines[i]
            m.brand = edited.brand
            m.stack = edited.stack
            m.addOn = edited.addOn
            m.pin = edited.pin
            m.plateSides = edited.plateSides
            m.bar = edited.bar
            m.settings = edited.settings
            if m != machines[i] || touched.machine != nil {
                machines[i] = m
                touched.machine = m.id
            }
            stored = edited.bare
        } else {
            stored.machineId = nil
        }
        if let i = exercises.firstIndex(where: { $0.id == edited.id }) {
            exercises[i] = stored
        } else {
            exercises.append(stored)
        }

        for c in before?.settings ?? [] where !edited.settings.contains(where: { $0.id == c.id }) {
            if let to = edited.settings.first(where: { $0.named(c.name) }) { touched.moved[c.id.uuidString] = to.id.uuidString }
        }
        guard !touched.moved.isEmpty else { return touched }
        for i in routines.indices where routines[i].move(touched.moved, of: edited.id) { touched.routines = true }
        for i in workouts.indices where workouts[i].move(touched.moved, of: edited.id) { touched.workouts.insert(workouts[i].id) }
        if active?.move(touched.moved, of: edited.id) == true { touched.active = true }
        return touched
    }
}

public extension Workout {
    /// Moves one exercise's setup values to other settings (old id → new id). True when any moved.
    mutating func move(_ moves: [String: String], of exerciseId: UUID) -> Bool {
        var changed = false
        for i in exercises.indices where exercises[i].exerciseId == exerciseId {
            if exercises[i].move(moves) { changed = true }
        }
        return changed
    }
}

public extension Routine {
    mutating func move(_ moves: [String: String], of exerciseId: UUID) -> Bool {
        var changed = false
        for i in exercises.indices where exercises[i].exerciseId == exerciseId {
            if exercises[i].move(moves) { changed = true }
        }
        return changed
    }
}

extension WorkoutExercise {
    mutating func move(_ moves: [String: String]) -> Bool {
        var changed = false
        for (from, to) in moves {
            guard let v = settings.removeValue(forKey: from) else { continue }
            if settings[to] == nil { settings[to] = v }
            changed = true
        }
        return changed
    }
}

public extension Previous {
    /// The latest finished entry of any exercise on the machine: where its seat was last set, for an exercise new to it.
    static func onMachine(_ machineId: UUID?, in workouts: [Workout], exercises byId: [UUID: Exercise],
                          excluding: UUID? = nil, before: Date? = nil) -> WorkoutExercise? {
        guard let machineId else { return nil }
        for w in workouts where w.id != excluding {
            if let before, w.start >= before { continue }
            if let e = w.exercises.first(where: { byId[$0.exerciseId]?.machineId == machineId && !$0.sets.isEmpty }) { return e }
        }
        return nil
    }
}
