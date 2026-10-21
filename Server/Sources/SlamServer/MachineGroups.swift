import Foundation
import SlamCore

/// Puts exercises onto machines from a list made off the server (`slam machines`). Running it again with the same
/// list changes nothing.
public enum MachineGroups {
    public struct Group: Decodable, Sendable {
        public var id: UUID?
        public var name: String
        public var brand: String?
        public var stack: [Double]?
        public var addOn: Double?
        public var pin: Bool?
        public var plateSides: Int?
        public var bar: Double?
        /// Setting names in order. Each keeps the id it has on the first exercise listed with it, so its logged
        /// values stay put. Left out: every exercise's settings.
        public var settings: [String]?
        public var exercises: [Ref]

        public init(id: UUID? = nil, name: String, brand: String? = nil, stack: [Double]? = nil, addOn: Double? = nil,
                    pin: Bool? = nil, plateSides: Int? = nil, bar: Double? = nil, settings: [String]? = nil, exercises: [UUID]) {
            self.id = id
            self.name = name
            self.brand = brand
            self.stack = stack
            self.addOn = addOn
            self.pin = pin
            self.plateSides = plateSides
            self.bar = bar
            self.settings = settings
            self.exercises = exercises.map(Ref.init)
        }
    }

    public struct Ref: Decodable, Sendable {
        public var id: UUID
    }

    struct File: Decodable {
        var machines: [Group]
    }

    public static func read(_ url: URL) throws -> [Group] {
        try JSONDecoder().decode(File.self, from: Data(contentsOf: url)).machines
    }

    /// Returns a line per machine saying what it holds.
    public static func apply(_ groups: [Group], to lib: inout Library) throws -> [String] {
        var lines: [String] = []
        for g in groups {
            let byId = Dictionary(lib.resolved.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let list = try g.exercises.map { ref in
                guard let e = byId[ref.id] else { throw MachineError.noExercise(ref.id, g.name) }
                return e
            }
            guard let first = list.first else { continue }
            let names = g.settings ?? list.flatMap { $0.settings.map(\.name) }
            var settings: [Configurable] = []
            for name in names where !settings.contains(where: { $0.named(name) }) {
                settings.append(list.lazy.compactMap { $0.settings.first { $0.named(name) } }.first ?? Configurable(name: name))
            }
            let id = g.id ?? lib.machines.first { $0.name == g.name }?.id ?? UUID()
            let machine = Machine(id: id, name: g.name, brand: g.brand ?? first.brand, stack: g.stack ?? first.stack,
                                  addOn: g.addOn, pin: g.pin ?? false, plateSides: g.plateSides ?? 0, bar: g.bar,
                                  settings: settings)
            if let i = lib.machines.firstIndex(where: { $0.id == id }) { lib.machines[i] = machine } else { lib.machines.append(machine) }
            var moved = 0
            for e in list {
                guard let m = lib.machine(id) else { break }
                let t = lib.save(e.moved(to: m))
                moved += t.workouts.count
            }
            let m = lib.machine(id) ?? machine
            lines.append("\(m.name): \(list.count) exercises, \(m.stack.count) weights"
                + (m.settings.isEmpty ? "" : ", settings " + m.settings.map(\.name).joined(separator: ", "))
                + (moved > 0 ? "; setup values moved in \(moved) workouts" : ""))
        }
        return lines
    }
}

public enum MachineError: Error, CustomStringConvertible {
    case noExercise(UUID, String)

    public var description: String {
        switch self {
        case let .noExercise(id, machine): "\(machine) lists exercise \(id), which the server does not have"
        }
    }
}
