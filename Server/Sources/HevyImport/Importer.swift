import Foundation
import SlamCore

/// One exercise as done in one workout, or as set up in a routine, with its note read.
struct Use {
    var day: String
    var gym: Int?
    /// Index into `Hevy.workouts`; nil for a routine.
    var workout: Int?
    var entry: Hevy.Entry
    var lines: [NoteLine]

    var kinds: [SetKind] { entry.sets.map { Map.kind($0.type) } }
    var working: [Int] { kinds.indices.filter { kinds[$0] != .warmup } }
}

/// One Slam exercise while the import runs: where it came from and what its sets showed.
final class Plan {
    var exercise: Exercise
    /// Hevy template ids, first used first.
    var templates: [String]
    var titles: [String]
    var rigging: Rigging
    var votes = Votes()
    /// Indices into `Importer.uses`, oldest first.
    var uses: [Int] = []
    var lrUses = 0
    /// Workouts per gym.
    var gyms: [Int: Int] = [:]
    var first: String?
    var last: String?
    var ruleBar: Double?
    /// The first day the bar is added to Hevy's weight.
    var barFrom: String?
    var renamed = false
    /// The Hevy templates behind it: name, first and last day, workouts.
    var parts: [(title: String, first: String, last: String, workouts: Int)] = []
    var settingCounts: [String: Int] = [:]
    var settingOrder: [String] = []

    // Filled while the sets are read.
    var slots: [Int: Set<Double>] = [:]
    var slotDay: [Int: String] = [:]
    var addOn: (day: String, kg: Double)?
    var bar: (day: String, kg: Double, source: String)?
    var settingsUsed: [String] = []

    init(exercise: Exercise, templates: [String], titles: [String], rigging: Rigging) {
        self.exercise = exercise
        self.templates = templates
        self.titles = titles
        self.rigging = rigging
    }

    /// The setting a number with no name most likely belongs to.
    var likelySetting: String? {
        settingOrder.max { settingCounts[$0]! < settingCounts[$1]! || (settingCounts[$0]! == settingCounts[$1]! && settingOrder.firstIndex(of: $0)! > settingOrder.firstIndex(of: $1)!) }
    }

    func record(_ load: Load, day: String, gym: Int?) {
        guard exercise.rig == .stack else { return }
        let g = gym ?? -1
        slots[g, default: []].insert(load.base)
        if day >= slotDay[g] ?? "" { slotDay[g] = day }
        if load.addOn > 0, day >= addOn?.day ?? "" { addOn = (day, load.addOn) }
    }
}

/// What the sets of one use became.
struct Applied {
    var sets: [WorkSet]
    var note: String
    /// Setting name and value, in the order first written.
    var settings: [(String, String)]
}

/// The id map kept next to the library, so a second run reuses every id.
struct ImportMap: Codable {
    var exercises: [String: UUID] = [:]
    var workouts: [String: UUID] = [:]
    var routines: [String: UUID] = [:]
    var folders: [String: UUID] = [:]
}

/// Builds a Slam library from a Hevy pull and keeps count of everything the dry-run report shows.
final class Importer {
    let hevy: Hevy
    let rules: Rules
    let grammar: Grammar
    let finder: GymFinder
    let previous: Library?
    let previousMap: ImportMap

    var uses: [Use] = []
    var workoutGym: [(gym: Int?, basis: GymFinder.Basis)] = []
    var plans: [Plan] = []
    var planOf: [String: Plan] = [:]
    var applied: [Int: Applied] = [:]
    var routineUses: [(routine: Int, use: Use, applied: Applied?)] = []
    var tally = Tally()
    var library = Library()
    var map = ImportMap()

    init(hevy: Hevy, rules: Rules, previous: Library? = nil, previousMap: ImportMap = ImportMap()) {
        self.hevy = hevy
        self.rules = rules
        grammar = Grammar(rules)
        finder = GymFinder(rules)
        self.previous = previous
        self.previousMap = previousMap
    }

    func run() throws {
        readWorkouts()
        planExercises()
        readRoutines()
        countSettings()
        for (i, u) in uses.enumerated() {
            if let p = planOf[u.entry.exerciseTemplateId] { applied[i] = apply(u, p, routine: false) }
        }
        for k in routineUses.indices {
            let u = routineUses[k].use
            if let p = planOf[u.entry.exerciseTemplateId] { routineUses[k].applied = apply(u, p, routine: true) }
        }
        finishExercises()
        try buildLibrary()
    }

    // MARK: Reading

    func readWorkouts() {
        for (wi, w) in hevy.workouts.enumerated() {
            let (gym, basis) = finder.workoutGym(w, hevy.templates)
            let g = (gym: gym, basis: basis)
            workoutGym.append(g)
            for e in w.exercises {
                uses.append(Use(day: w.day, gym: g.gym, workout: wi, entry: e, lines: read(e.notes, gym: g.gym)))
            }
        }
    }

    func readRoutines() {
        for (ri, r) in hevy.routines.enumerated() {
            let latest = hevy.workouts.indices.last { hevy.workouts[$0].routineId == r.id }
            let gym = latest.map { workoutGym[$0].gym } ?? finder.index(rules.currentGym)
            for e in r.exercises {
                routineUses.append((ri, Use(day: "9999-12-31", gym: gym, workout: nil, entry: e, lines: read(e.notes, gym: gym)), nil))
            }
        }
    }

    func read(_ notes: String?, gym: Int?) -> [NoteLine] {
        let addOns = finder.addOns(gym)
        return (notes ?? "").components(separatedBy: "\n").compactMap { grammar.read($0, addOns: addOns) }
    }

    /// The sets a loadout is about; nil when its set number is past the last set.
    static func targets(_ l: Loadout, _ index: Int?, _ kinds: [SetKind]) -> [Int]? {
        let work = kinds.indices.filter { kinds[$0] != .warmup }
        if let i = index { return i >= 1 && i <= work.count ? [work[i - 1]] : nil }
        switch l.prefix {
        case "wu": return kinds.indices.filter { kinds[$0] == .warmup }
        case "wo": return work
        default: return Array(kinds.indices)
        }
    }

    // MARK: Exercises

    struct Facts {
        var template: Hevy.Template
        var uses: [Int] = []
        var workouts = Set<Int>()
        var first = ""
        var last = ""
        var gyms: [Int: Int] = [:]
        var votes = Votes()
        var barDay: String?
        var lrUses = 0
        var rigging = Rigging(equipment: .other)
        var uni = false
    }

    func planExercises() {
        var facts: [String: Facts] = [:]
        var order: [String] = []
        for (i, u) in uses.enumerated() {
            let tid = u.entry.exerciseTemplateId
            if facts[tid] == nil {
                let t = hevy.templates[tid] ?? Hevy.Template(id: tid, title: u.entry.title, type: guessType(u.entry),
                                                             primaryMuscleGroup: nil, secondaryMuscleGroups: nil,
                                                             equipment: nil, isCustom: true)
                facts[tid] = Facts(template: t, first: u.day)
                order.append(tid)
            }
            var f = facts[tid]!
            f.uses.append(i)
            f.last = u.day
            if let w = u.workout, f.workouts.insert(w).inserted, let g = u.gym { f.gyms[g, default: 0] += 1 }
            if u.lines.contains(where: { $0.frags.contains { if case .sides = $0.value { return true }; return false } }) {
                f.lrUses += 1
            }
            for line in u.lines where !line.plan {
                for (_, l) in line.loads {
                    guard let tg = Importer.targets(l, line.setIndex, u.kinds) else { continue }
                    let kgs = tg.compactMap { u.entry.sets[$0].weightKg }
                    if let k = Rigs.vote(l, kgs: kgs, rules: rules) {
                        f.votes[keyPath: k] += 1
                        if k == \Votes.bar, f.barDay == nil { f.barDay = u.day }
                    }
                }
            }
            facts[tid] = f
        }
        for tid in order {
            var f = facts[tid]!
            let t = f.template
            f.rigging = Rigs.decide(type: Map.type(t.type), hevy: t.equipment, name: t.title,
                                    primary: Map.muscle(t.primaryMuscleGroup), votes: f.votes, rules: rules)
            f.uni = Names.onePerSide(t.title) || Double(f.lrUses) >= 0.1 * Double(f.uses.count)
            facts[tid] = f
        }

        for chain in chains(order, facts) {
            let fs = chain.map { facts[$0]! }
            let latest = fs.last!.template
            let votes = fs.reduce(Votes()) { $0 + $1.votes }
            let type = Map.type(latest.type)
            let primary = Map.muscle(latest.primaryMuscleGroup)
            let rig = Rigs.decide(type: type, hevy: latest.equipment, name: latest.title, primary: primary, votes: votes, rules: rules)
            let useCount = fs.reduce(0) { $0 + $1.uses.count }
            let lr = fs.reduce(0) { $0 + $1.lrUses }
            let ex = Exercise(name: latest.title, type: type, equipment: rig.equipment, primary: primary,
                              secondary: (latest.secondaryMuscleGroups ?? []).map(Map.muscle).filter { $0 != primary },
                              unilateral: Names.onePerSide(latest.title) || Double(lr) >= 0.1 * Double(useCount),
                              plateSides: rig.equipment == .machine ? rig.plateSides : 0, hevyId: chain[0])
            let p = Plan(exercise: ex, templates: chain, titles: fs.map(\.template.title), rigging: rig)
            p.votes = votes
            p.uses = fs.flatMap(\.uses).sorted()
            p.lrUses = lr
            p.first = fs.first!.first
            p.parts = fs.map { ($0.template.title, $0.first, $0.last, $0.workouts.count) }
            p.last = fs.map(\.last).max()
            for f in fs { p.gyms.merge(f.gyms, uniquingKeysWith: +) }
            add(p)
        }
        // Custom templates never used still become exercises.
        for t in hevy.templates.values.sorted(by: { $0.title < $1.title }) where (t.isCustom ?? false) && facts[t.id] == nil {
            let type = Map.type(t.type)
            let primary = Map.muscle(t.primaryMuscleGroup)
            let rig = Rigs.decide(type: type, hevy: t.equipment, name: t.title, primary: primary, votes: Votes(), rules: rules)
            let ex = Exercise(name: t.title, type: type, equipment: rig.equipment, primary: primary,
                              secondary: (t.secondaryMuscleGroups ?? []).map(Map.muscle).filter { $0 != primary },
                              unilateral: Names.onePerSide(t.title), plateSides: rig.plateSides, hevyId: t.id)
            add(Plan(exercise: ex, templates: [t.id], titles: [t.title], rigging: rig))
        }
        for p in plans { finishPlan(p, facts) }
        nameExercises()
    }

    private func add(_ p: Plan) {
        plans.append(p)
        for t in p.templates { planOf[t] = p }
    }

    /// Templates that are one exercise renamed over time, in date order.
    func chains(_ order: [String], _ facts: [String: Facts]) -> [[String]] {
        let sorted = order.sorted { (facts[$0]!.first, $0) < (facts[$1]!.first, $1) }
        var chains: [[String]] = []
        for t in sorted {
            var best: (Int, Double)?
            for (ci, c) in chains.enumerated() {
                guard let j = fits(facts[c.last!]!, facts[t]!) else { continue }
                if best.map({ j > $0.1 }) ?? true { best = (ci, j) }
            }
            if let best { chains[best.0].append(t) } else { chains.append([t]) }
        }
        return chains
    }

    /// How well `b` reads as `a` renamed: nil when it cannot be.
    func fits(_ a: Facts, _ b: Facts) -> Double? {
        let ta = a.template, tb = b.template
        guard ta.type == tb.type else { return nil }
        let squash = { (s: String) in s.lowercased().split(separator: " ").joined(separator: " ") }
        if squash(ta.title) == squash(tb.title) { return 2 }
        guard ta.primaryMuscleGroup == tb.primaryMuscleGroup, a.rigging.key == b.rigging.key, a.uni == b.uni,
              a.last < b.first, !Set(a.gyms.keys).isDisjoint(with: b.gyms.keys) else { return nil }
        let cableA = Rigs.word(ta.title, "cable"), cableB = Rigs.word(tb.title, "cable")
        let machineA = Rigs.word(ta.title, "machine"), machineB = Rigs.word(tb.title, "machine")
        if (cableA && machineB && !cableB) || (cableB && machineA && !cableA) { return nil }
        let x = Names.tokens(ta.title, finder, stop: rules.nameStopWords)
        let y = Names.tokens(tb.title, finder, stop: rules.nameStopWords)
        guard !x.isEmpty, !y.isEmpty, x.isSubset(of: y) || y.isSubset(of: x),
              x.symmetricDifference(y).isDisjoint(with: Names.variantWords) else { return nil }
        let j = Double(x.intersection(y).count) / Double(x.union(y).count)
        return j >= 0.5 ? j : nil
    }

    private func finishPlan(_ p: Plan, _ facts: [String: Facts]) {
        guard p.exercise.equipment == .barbell else { return }
        p.ruleBar = rules.bars.first { b in p.titles.contains { Rx(b.name, caseless: true).matches($0) } }?.kg
        let hevyBarbell = p.templates.contains { facts[$0]?.template.equipment == "barbell" }
        let named = p.titles.contains { t in
            rules.bars.contains { $0.barbell && Rx($0.name, caseless: true).matches(t) }
                || (["barbell"] + rules.barWords).contains { Rigs.word(t, $0) }
        }
        p.barFrom = hevyBarbell || named ? p.first : p.templates.compactMap { facts[$0]?.barDay }.min()
    }

    private func guessType(_ e: Hevy.Entry) -> String {
        if e.sets.contains(where: { $0.distanceMeters != nil }) { return "distance_duration" }
        if e.sets.contains(where: { $0.durationSeconds != nil }) && !e.sets.contains(where: { $0.reps != nil }) { return "duration" }
        if !e.sets.contains(where: { $0.weightKg != nil }) { return "reps_only" }
        return "weight_reps"
    }

    /// Clean names: gym marks off, the brand in front, capitals fixed; clashes told apart.
    func nameExercises() {
        var markerGym: [ObjectIdentifier: Int] = [:]
        for p in plans {
            let latest = p.titles.last!
            let (stripped, gym) = finder.stripMarkers(latest)
            var name = Names.tidy(stripped)
            if name.isEmpty { name = latest }
            let machine = [.machine, .cable].contains(p.exercise.equipment)
            if machine {
                p.exercise.brand = brand(p) ?? ""
            }
            if let gym {
                markerGym[ObjectIdentifier(p)] = gym
                if machine, let b = rules.gyms[gym].brand, !name.lowercased().hasPrefix(b.lowercased()) {
                    name = b + " " + name
                }
            }
            p.exercise.name = name
        }
        // Names that clash after the marks came off get their gym back.
        for _ in 0 ..< 3 {
            let groups = Dictionary(grouping: plans) { $0.exercise.name.lowercased() }.filter { $0.value.count > 1 }
            if groups.isEmpty { break }
            for (_, ps) in groups {
                for p in ps {
                    guard let g = markerGym[ObjectIdentifier(p)] else { continue }
                    if let n = rules.gyms[g].name, !p.exercise.name.hasSuffix("(\(n))") {
                        p.exercise.name += " (\(n))"
                    } else {
                        p.exercise.name = p.titles.last!
                    }
                    markerGym[ObjectIdentifier(p)] = nil
                }
            }
        }
        for p in plans { p.renamed = !p.titles.contains(p.exercise.name) || p.templates.count > 1 }
    }

    /// Brands only go on machines: one named for a gym gets that gym's brand, and so does every machine
    /// used only at a gym whose machines are all one brand.
    private func brand(_ p: Plan) -> String? {
        for t in p.titles.reversed() {
            if let g = finder.exerciseGym(t), let b = rules.gyms[g].brand { return b }
        }
        let gyms = Set(p.gyms.keys)
        if gyms.count == 1, let g = gyms.first, rules.gyms[g].brandAllMachines { return rules.gyms[g].brand }
        return nil
    }

    // MARK: Settings

    func settingName(_ raw: String) -> String {
        let n = rules.settingNames[raw] ?? raw
        return n.prefix(1).uppercased() + n.dropFirst()
    }

    func countSettings() {
        let all = uses.map { ($0, false) } + routineUses.map { ($0.use, true) }
        for (u, _) in all {
            guard let p = planOf[u.entry.exerciseTemplateId] else { continue }
            for line in u.lines where !line.plan {
                for f in line.frags {
                    let n: String?
                    switch f.value {
                    case .setting(let name, _), .shows(let name, _): n = name
                    default: continue
                    }
                    guard let n else { continue }
                    let name = settingName(n)
                    if p.settingCounts[name] == nil { p.settingOrder.append(name) }
                    p.settingCounts[name, default: 0] += 1
                }
            }
        }
    }

    // MARK: Sets

    /// The loads a loadout can be on this exercise's rig.
    func candidates(_ l: Loadout, _ p: Plan, bar: Double) -> [Load] {
        let desc = { (x: [Double]) in x.sorted(by: >) }
        let flat = ["L_COUNT", "L_SUM", "L_SPACED", "L_SINGLE", "L_LEAD"]
        switch p.exercise.rig {
        case .stack:
            guard let b = l.base, ["L_PIN", "L_SUM", "L_SPACED", "L_SINGLE", "L_LEAD", "L_MAX", "L_BASE_COUNT"].contains(l.shape)
            else { return [] }
            return [Load(base: b, addOn: l.addOn ?? 0, plates: desc(l.plates))]
        case .dumbbell:
            guard let b = l.base, ["L_DB", "L_BASE_COUNT", "L_SUM", "L_SPACED", "L_SINGLE", "L_LEAD", "L_PIN"].contains(l.shape)
            else { return [] }
            return [Load(base: b, plates: desc(Array(l.numbers.dropFirst())))]
        case .barbell:
            let plates = l.shape == "L_PERSIDE" ? l.plates : (flat.contains(l.shape) ? l.numbers : [])
            guard !plates.isEmpty else { return [] }
            return [Load(base: bar == 0 ? 0 : (l.bar ?? bar), plates: desc(plates), sides: 2)]
        case .plateLoaded:
            let plates = l.shape == "L_PERSIDE" ? l.plates : (flat.contains(l.shape) ? l.numbers : [])
            guard !plates.isEmpty else { return [] }
            let k = max(1, p.exercise.plateSides)
            let sides = l.shape == "L_PERSIDE" ? [2] : [k, 3 - k]
            return sides.map { Load(base: l.bar ?? 0, plates: desc(plates), sides: $0) }
        case .plain:
            return []
        }
    }

    func apply(_ u: Use, _ p: Plan, routine: Bool) -> Applied {
        let hs = u.entry.sets
        let kinds = u.kinds
        let work = u.working
        let uni = p.exercise.unilateral
        let lines = u.lines
        var sets = hs.indices.map { i in
            WorkSet(kind: kinds[i], kg: hs[i].weightKg, reps: hs[i].reps, seconds: hs[i].durationSeconds,
                    meters: hs[i].distanceMeters, done: !routine)
        }
        var used: [Set<Int>] = lines.map { line in
            Set(line.frags.indices.filter { if case .ignored = line.frags[$0].value { return true }; return false })
        }
        let live = lines.indices.filter { !lines[$0].plan }
        var setBar = [Double](repeating: 0, count: hs.count)

        // Hevy holds a barbell's plates only; Slam's weight has the bar in it.
        if p.exercise.equipment == .barbell && p.exercise.type.hasKg {
            let loads = live.flatMap { lines[$0].loads.map(\.1) }
            let inPeriod = routine || (p.barFrom.map { u.day >= $0 } ?? false)
            if inPeriod && !loads.contains(where: { $0.shape == "L_DB" }) {
                let named = loads.first { $0.bar != nil }?.bar
                let fallback = named ?? (routine ? p.bar?.kg : nil) ?? p.ruleBar ?? 20
                let logged = hs.compactMap(\.weightKg)
                let withBar = loads.contains { l in
                    l.shape == "L_PERSIDE" && l.bar != nil && logged.contains { abs($0 - l.total!) < Rigs.eps }
                        && !logged.contains { abs($0 - l.plateTotal) < Rigs.eps }
                }
                if withBar {
                    if !routine { tally.loggedWithBar[p.exercise.name, default: 0] += 1 }
                } else {
                    var source = named != nil ? "note" : p.ruleBar != nil ? "rule" : "default"
                    var last = fallback
                    for i in hs.indices {
                        guard let k = hs[i].weightKg else { continue }
                        let code = rules.barCode(k)
                        let b = code?.bar ?? fallback
                        if code != nil { source = "weight decimals" }
                        sets[i].kg = ((k - (code?.code ?? 0) + b) * 1000).rounded() / 1000
                        setBar[i] = b
                        last = b
                    }
                    if !routine, u.day >= p.bar?.day ?? "" { p.bar = (u.day, last, source) }
                }
            }
        }

        // Loadouts: each becomes the load of the sets whose weight it adds up to.
        for li in lines.indices {
            let line = lines[li]
            if line.plan {
                if !routine { tally.planned += line.loads.count }
                continue
            }
            for fi in line.frags.indices {
                let l: Loadout
                switch line.frags[fi].value {
                case .load(let x): l = x
                case .increment:
                    miss("no total (extras or an increment only)", u, p, line, nil, routine)
                    continue
                default: continue
                }
                if !routine { tally.loadouts += 1 }
                guard let total = l.total else {
                    miss("no total (extras or an increment only)", u, p, line, nil, routine)
                    continue
                }
                guard let tg = Importer.targets(l, line.setIndex, kinds) else {
                    miss("set number past the last set", u, p, line, total, routine)
                    continue
                }
                let weighed = tg.filter { sets[$0].kg != nil }
                guard !weighed.isEmpty else {
                    miss("no weight logged", u, p, line, total, routine)
                    continue
                }
                var hit = false
                var fits = false
                for i in weighed {
                    let cands = candidates(l, p, bar: setBar[i])
                    if !cands.isEmpty { fits = true }
                    guard let c = cands.first(where: { abs($0.total - sets[i].kg!) < Rigs.eps }) else { continue }
                    hit = true
                    if sets[i].load == nil {
                        sets[i].load = c
                        if !routine { p.record(c, day: u.day, gym: u.gym) }
                    }
                }
                if hit {
                    used[li].insert(fi)
                    if !routine { tally.matched += 1 }
                    continue
                }
                if ["L_SINGLE", "L_LEAD"].contains(l.shape), let v = l.base,
                   weighed.contains(where: { abs(sets[$0].kg! - v) < Rigs.eps || abs((hs[$0].weightKg ?? .nan) - v) < Rigs.eps }) {
                    used[li].insert(fi)
                    if !routine { tally.restated += 1 }
                    continue
                }
                let why = fits ? reason(l, p, weighed, sets, setBar, u.gym) : "shape does not fit a \(rigName(p.exercise.rig))"
                miss(why, u, p, line, candidates(l, p, bar: setBar[weighed[0]]).first?.total ?? total, routine,
                     logged: work.compactMap { sets[$0].kg })
            }
        }

        // Left and right reps.
        var sideAt: [Int: (Int, Int, Int, Int)] = [:]
        var sideRun: [(Int, Int, Int, Int)?] = []
        for (li, line) in lines.enumerated() {
            guard let fi = line.frags.firstIndex(where: { if case .sides = $0.value { return true }; return false }),
                  case .sides(let a, let b) = line.frags[fi].value else { continue }
            let v = Int(a).flatMap { l in Int(b).map { (l, $0, li, fi) } }
            if let i = line.setIndex {
                if let v, i >= 1, i <= work.count { sideAt[work[i - 1]] = v }
            } else {
                sideRun.append(v)
            }
        }
        if uni {
            var put = sideAt
            if sideRun.count == work.count, sideRun.allSatisfy({ $0 != nil }) {
                for (k, v) in sideRun.enumerated() where put[work[k]] == nil { put[work[k]] = v! }
            } else if !sideRun.isEmpty, !routine {
                tally.sidesUnplaced += sideRun.count
            }
            for (i, v) in put {
                sets[i].reps = v.0
                sets[i].repsR = v.1
                used[v.2].insert(v.3)
            }
        } else if (!sideAt.isEmpty || !sideRun.isEmpty) && !routine {
            tally.sidesOnBilateral[p.exercise.name, default: 0] += 1
        }

        // Reps in reserve, never on a warm-up.
        var rirAt: [Int: (Int, Int?, Int, [Int])] = [:]
        var rirRun: [(Int, Int?, Int, [Int])] = []
        for (li, line) in lines.enumerated() {
            let fs = line.frags.indices.filter {
                switch line.frags[$0].value {
                case .rir, .fail: true
                default: false
                }
            }
            guard !fs.isEmpty else { continue }
            func value(_ fi: Int) -> Int {
                if case .rir(let a, let b) = line.frags[fi].value { return Frag.Value.rirValue(a, b) }
                return 0
            }
            let two = fs.count >= 2 && uni
            let v = (value(fs[0]), two ? value(fs[1]) : nil, li, two ? Array(fs.prefix(2)) : [fs[0]])
            if let i = line.setIndex {
                if i >= 1, i <= work.count { rirAt[work[i - 1]] = v }
            } else {
                rirRun.append(v)
            }
        }
        var rirPut = rirAt
        if rirRun.count == work.count {
            for (k, v) in rirRun.enumerated() where rirPut[work[k]] == nil { rirPut[work[k]] = v }
        } else if !rirRun.isEmpty, !routine {
            tally.rirUnplaced += rirRun.count
        }
        for (i, v) in rirPut {
            sets[i].rir = v.0
            sets[i].rirR = v.1 ?? (uni ? v.0 : nil)
            for fi in v.3 { used[v.2].insert(fi) }
        }
        if uni {
            for i in sets.indices {
                if sets[i].repsR == nil { sets[i].repsR = sets[i].reps }
                if sets[i].rirR == nil { sets[i].rirR = sets[i].rir }
            }
        }

        // Settings: a named one, or the shown number of an unnamed one.
        var settings: [(String, String)] = []
        for li in live {
            let line = lines[li]
            for fi in line.frags.indices {
                let name: String?, value: String
                switch line.frags[fi].value {
                case .setting(let n, let v): (name, value) = (n, v)
                case .shows(let n, let v): (name, value) = (n, v)
                default: continue
                }
                let n: String
                if let name {
                    n = settingName(name)
                } else {
                    n = p.likelySetting ?? rules.defaultSetting
                    tally.guess(p.exercise.name, n, line.raw, guessed: p.likelySetting != nil)
                }
                if !settings.contains(where: { $0.0 == n }) { settings.append((n, value)) }
                used[li].insert(fi)
            }
        }

        // What is left of each line is the note.
        var kept: [String] = []
        for (li, line) in lines.enumerated() {
            let left = line.leftover(used[li])
            if !left.isEmpty { kept.append(left) }
            guard !routine else { continue }
            tally.count(line, left: left, used: used[li], day: u.day, exercise: u.entry.title)
        }
        return Applied(sets: sets, note: kept.joined(separator: "\n"), settings: settings)
    }

    private func reason(_ l: Loadout, _ p: Plan, _ weighed: [Int], _ sets: [WorkSet], _ setBar: [Double], _ gym: Int?) -> String {
        let t = candidates(l, p, bar: setBar[weighed[0]]).first?.total ?? l.total!
        let d = weighed.map { sets[$0].kg! - t }.min { abs($0) < abs($1) }!
        if abs(d) <= 0.5 { return "off by 0.5 kg or less" }
        if abs(d - 1) < Rigs.eps && l.shape == "L_PIN" && !l.plates.isEmpty { return "logged = note + 1 (pin)" }
        if finder.addOns(gym).contains(where: { abs(d - $0) < Rigs.eps }) { return "logged = note + an add-on" }
        if sets.contains(where: { $0.kg.map { abs($0 - t) < Rigs.eps } ?? false }) { return "matches another set" }
        return "stale note or other"
    }

    private func miss(_ why: String, _ u: Use, _ p: Plan, _ line: NoteLine, _ value: Double?, _ routine: Bool,
                      logged: [Double] = []) {
        guard !routine else { return }
        tally.miss(why, day: u.day, exercise: p.exercise.name, line: line.raw, value: value, logged: logged)
    }

    func rigName(_ r: Rig) -> String {
        switch r {
        case .stack: "stack"
        case .plateLoaded: "plate-loaded machine"
        case .barbell: "barbell"
        case .dumbbell: "dumbbell"
        case .plain: "plain weight"
        }
    }

    // MARK: Finishing

    func finishExercises() {
        for p in plans {
            if p.exercise.rig == .stack, let g = p.slotDay.max(by: { $0.value < $1.value })?.key {
                p.exercise.stack = p.slots[g]!.sorted()
            }
            if p.exercise.rig == .stack { p.exercise.addOn = p.addOn?.kg }
            if p.exercise.equipment == .barbell { p.exercise.bar = p.bar?.kg ?? p.ruleBar ?? 20 }
        }
        var names: [ObjectIdentifier: [String]] = [:]
        for (i, u) in uses.enumerated() {
            guard let p = planOf[u.entry.exerciseTemplateId], let a = applied[i] else { continue }
            for (n, _) in a.settings where !(names[ObjectIdentifier(p)] ?? []).contains(n) { names[ObjectIdentifier(p), default: []].append(n) }
        }
        for r in routineUses {
            guard let p = planOf[r.use.entry.exerciseTemplateId], let a = r.applied else { continue }
            for (n, _) in a.settings where !(names[ObjectIdentifier(p)] ?? []).contains(n) { names[ObjectIdentifier(p), default: []].append(n) }
        }
        let prevExercises = Dictionary((previous?.exercises ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // Ids from the last run: an exercise keeps its first template's, then any free one of its others.
        var taken = Set<UUID>()
        func old(_ t: String) -> UUID? {
            previousMap.exercises[t] ?? previous?.exercises.first { $0.hevyId == t }?.id
        }
        var kept: [ObjectIdentifier: UUID] = [:]
        for p in plans { if let id = old(p.templates[0]), taken.insert(id).inserted { kept[ObjectIdentifier(p)] = id } }
        for p in plans where kept[ObjectIdentifier(p)] == nil {
            if let id = p.templates.dropFirst().lazy.compactMap(old).first(where: { !taken.contains($0) }) {
                taken.insert(id)
                kept[ObjectIdentifier(p)] = id
            }
        }
        for p in plans {
            if let id = kept[ObjectIdentifier(p)] { p.exercise.id = id }
            let old = prevExercises[p.exercise.id]?.settings ?? []
            let cardio = p.exercise.equipment == .cardio || p.exercise.type.hasTime
            p.exercise.settings = (names[ObjectIdentifier(p)] ?? []).map { n in
                Configurable(id: old.first { $0.name == n }?.id ?? UUID(), name: n,
                             perWorkout: cardio && ["incline", "level", "speed", "resistance"].contains(n.lowercased()))
            }
            p.settingsUsed = names[ObjectIdentifier(p)] ?? []
        }
    }

    func entry(_ p: Plan, _ a: Applied, _ e: Hevy.Entry, reuse: WorkoutExercise?) -> WorkoutExercise {
        var we = WorkoutExercise(id: reuse?.id ?? UUID(), exerciseId: p.exercise.id, note: a.note, sets: a.sets,
                                 supersetId: e.supersetId)
        if let reuse {
            for i in we.sets.indices where i < reuse.sets.count { we.sets[i].id = reuse.sets[i].id }
        }
        for (n, v) in a.settings {
            if let c = p.exercise.settings.first(where: { $0.name == n }) { we[setting: c.id] = v }
        }
        return we
    }

    func buildLibrary() throws {
        let prev = previous ?? Library()
        var gymIds: [String: UUID] = [:]
        for g in rules.gyms {
            guard let n = g.name, gymIds[n] == nil else { continue }
            let id = prev.gyms.first { $0.name == n }?.id ?? UUID()
            gymIds[n] = id
            library.gyms.append(Gym(id: id, name: n))
        }
        var folderIds: [Int: UUID] = [:]
        for f in hevy.folders {
            let id = previousMap.folders[String(f.id)] ?? prev.folders.first { $0.name == f.title }?.id ?? UUID()
            folderIds[f.id] = id
            map.folders[String(f.id)] = id
            library.folders.append(Folder(id: id, name: f.title))
        }
        var routineIds: [String: UUID] = [:]
        for (ri, r) in hevy.routines.enumerated() {
            let old = prev.routines.first { $0.hevyId == r.id }
            let id = old?.id ?? previousMap.routines[r.id] ?? UUID()
            routineIds[r.id] = id
            map.routines[r.id] = id
            var exs: [WorkoutExercise] = []
            for ru in routineUses where ru.routine == ri {
                guard let p = planOf[ru.use.entry.exerciseTemplateId], let a = ru.applied else { continue }
                let n = exs.count
                let reuse = old.flatMap { n < $0.exercises.count && $0.exercises[n].exerciseId == p.exercise.id ? $0.exercises[n] : nil }
                exs.append(entry(p, a, ru.use.entry, reuse: reuse))
            }
            library.routines.append(Routine(id: id, name: r.title, folderId: r.folderId.flatMap { folderIds[$0] },
                                            exercises: exs, hevyId: r.id))
        }
        let prevWorkouts = Dictionary(prev.workouts.compactMap { w in w.hevyId.map { ($0, w) } }, uniquingKeysWith: { a, _ in a })
        var byWorkout: [Int: [Int]] = [:]
        for (i, u) in uses.enumerated() { if let w = u.workout { byWorkout[w, default: []].append(i) } }
        for (wi, w) in hevy.workouts.enumerated() {
            guard let start = Hevy.date(w.startTime) else {
                throw CocoaError(.coderReadCorrupt, userInfo: [NSDebugDescriptionErrorKey: "workout \(w.id) has no readable start"])
            }
            let old = prevWorkouts[w.id]
            let id = old?.id ?? previousMap.workouts[w.id] ?? UUID()
            map.workouts[w.id] = id
            var exs: [WorkoutExercise] = []
            for i in byWorkout[wi] ?? [] {
                guard let p = planOf[uses[i].entry.exerciseTemplateId], let a = applied[i] else { continue }
                let n = exs.count
                let reuse = old.flatMap { n < $0.exercises.count && $0.exercises[n].exerciseId == p.exercise.id ? $0.exercises[n] : nil }
                exs.append(entry(p, a, uses[i].entry, reuse: reuse))
            }
            let gym = finder.name(workoutGym[wi].gym).flatMap { gymIds[$0] }
            library.workouts.append(Workout(id: id, title: w.title, start: start, end: w.endTime.flatMap(Hevy.date),
                                            notes: (w.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                                            gymId: gym, routineId: w.routineId.flatMap { routineIds[$0] },
                                            exercises: exs, hevyId: w.id))
        }
        library.workouts.sort { $0.start > $1.start }
        library.exercises = plans.map(\.exercise).sorted { $0.name.lowercased() < $1.name.lowercased() }
        for p in plans { for t in p.templates { map.exercises[t] = p.exercise.id } }
        library.settings = Settings(restSeconds: prev.settings.restSeconds, warmupRestSeconds: prev.settings.warmupRestSeconds,
                                    gymId: rules.currentGym.flatMap { gymIds[$0] })
    }
}
