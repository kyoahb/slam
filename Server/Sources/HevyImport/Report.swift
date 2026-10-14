import Foundation
import SlamCore

/// The numbers of a dry run, as written to summary.json.
struct Summary: Encodable {
    struct Counts: Encodable {
        var workouts = 0
        var routines = 0
        var folders = 0
        var exercises = 0
        var templatesUsed = 0
        var templatesMerged = 0
        var sets = 0
        var setsOnRigsWithParts = 0
        var setsWithBreakdown = 0
        var loadoutLines = 0
        var loadoutsMatched = 0
        var loadoutsRestated = 0
        var loadoutsOnPlanLines = 0
        var misses = 0
        var gyms = 0
    }

    struct Notes: Encodable {
        var lines = 0
        var kept = 0
        var dropped = 0
        var droppedByKind: [String: Int] = [:]
        var usedByKind: [String: Int] = [:]
        var rirLinesNotPlaced = 0
        var sideLinesNotPlaced = 0
    }

    struct Checks: Encodable {
        var merges = 0
        var renames = 0
        var guessedSettings = 0
        var lowConfidenceEquipment = 0
        var lrOnBilateral = 0
        var gymAgainstTimeline = 0
        var barbells = 0
        var entriesWithBarInHevy = 0
        var stacksFromSeveralGyms = 0
    }

    var rules: String
    var counts = Counts()
    var misses: [String: Int] = [:]
    var notes = Notes()
    var gymBasis: [String: Int] = [:]
    var checks = Checks()
}

/// The dry-run report: what the import would write, and what to look at before it does.
struct Report {
    let im: Importer
    let rulesPath: String

    private var lib: Library { im.library }
    private var tally: Tally { im.tally }

    // MARK: Checks

    var merges: [Plan] { im.plans.filter { $0.templates.count > 1 } }
    var renames: [Plan] { im.plans.filter { $0.templates.count == 1 && $0.renamed } }
    var doubts: [Plan] { im.plans.filter { $0.rigging.doubt != nil && !$0.uses.isEmpty } }
    var barbells: [Plan] { im.plans.filter { $0.exercise.equipment == .barbell && !$0.uses.isEmpty } }
    var mixedStacks: [Plan] { im.plans.filter { $0.exercise.rig == .stack && $0.slots.count > 1 } }

    /// Workouts whose gym came from their own words or exercises and differs from the timeline.
    var gymFlags: [(day: String, title: String, gym: String, timeline: String, basis: String)] {
        im.hevy.workouts.indices.compactMap { i in
            let w = im.hevy.workouts[i]
            let (g, basis) = im.workoutGym[i]
            guard basis == .text || basis == .exercises else { return nil }
            let gym = im.finder.name(g) ?? "unknown gym"
            let line = im.rules.timelineGym(w.day) ?? "none"
            return gym == line ? nil : (w.day, w.title, gym, line, basis.rawValue)
        }
    }

    func workouts(_ p: Plan) -> Int { Set(p.uses.compactMap { im.uses[$0].workout }).count }

    // MARK: Summary

    func summary() -> Summary {
        var s = Summary(rules: rulesPath)
        let sets = lib.workouts.flatMap { w in w.exercises.flatMap(\.sets) }
        let rigOf = Dictionary(lib.exercises.map { ($0.id, $0.rig) }, uniquingKeysWith: { a, _ in a })
        s.counts.workouts = lib.workouts.count
        s.counts.routines = lib.routines.count
        s.counts.folders = lib.folders.count
        s.counts.exercises = lib.exercises.count
        s.counts.templatesUsed = Set(im.uses.map(\.entry.exerciseTemplateId)).count
        s.counts.templatesMerged = merges.reduce(0) { $0 + $1.templates.count }
        s.counts.sets = sets.count
        s.counts.setsOnRigsWithParts = lib.workouts.flatMap { w in
            w.exercises.filter { [.stack, .barbell, .dumbbell, .plateLoaded].contains(rigOf[$0.exerciseId] ?? .plain) }.flatMap(\.sets)
        }.filter { $0.kg != nil }.count
        s.counts.setsWithBreakdown = sets.filter { $0.load != nil }.count
        s.counts.loadoutLines = tally.loadouts
        s.counts.loadoutsMatched = tally.matched
        s.counts.loadoutsRestated = tally.restated
        s.counts.loadoutsOnPlanLines = tally.planned
        s.counts.misses = tally.missCount
        s.counts.gyms = lib.gyms.count
        s.misses = tally.misses
        s.notes = Summary.Notes(lines: tally.lines, kept: tally.lines - tally.dropped, dropped: tally.dropped,
                                droppedByKind: tally.droppedByKind, usedByKind: tally.usedByKind,
                                rirLinesNotPlaced: tally.rirUnplaced, sideLinesNotPlaced: tally.sidesUnplaced)
        for (_, b) in im.workoutGym { s.gymBasis[b.rawValue, default: 0] += 1 }
        s.checks = Summary.Checks(merges: merges.count, renames: renames.count, guessedSettings: tally.guesses.count,
                                  lowConfidenceEquipment: doubts.count, lrOnBilateral: tally.sidesOnBilateral.count,
                                  gymAgainstTimeline: gymFlags.count, barbells: barbells.count,
                                  entriesWithBarInHevy: tally.loggedWithBar.values.reduce(0, +),
                                  stacksFromSeveralGyms: mixedStacks.count)
        return s
    }

    // MARK: HTML

    func html() -> String {
        let s = summary()
        var o = ""
        o += "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">"
        o += "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><meta name=\"color-scheme\" content=\"dark\">"
        o += "<title>Hevy import dry run</title><style>\(Report.css)</style></head><body><main>"
        o += "<h1>Hevy → Slam: dry run</h1>"
        o += "<p class=\"muted\">Nothing has been written to the phone or the server. Rules: \(h(rulesPath)).</p>"

        // 1. Headline
        let c = s.counts
        o += "<div class=\"tiles\">"
        for (label, v) in [("Workouts", "\(c.workouts)"), ("Routines", "\(c.routines)"), ("Exercises", "\(c.exercises)"),
                           ("Sets", "\(c.sets)"), ("Sets with full breakdown", "\(c.setsWithBreakdown)"),
                           ("Misses", "\(c.misses)")] {
            o += "<div class=\"tile\"><b>\(v)</b><span class=\"muted\">\(label)</span></div>"
        }
        o += "</div>"
        o += "<p class=\"muted\">\(c.setsWithBreakdown) of \(c.setsOnRigsWithParts) weighted sets on stacks, bars, dumbbells and plate-loaded machines have their parts. "
        o += "\(c.loadoutLines) loadouts read: \(c.loadoutsMatched) matched, \(c.loadoutsRestated) only repeat the weight, \(c.misses) missed; "
        o += "\(c.loadoutsOnPlanLines) more sit on plan lines. \(c.templatesUsed) Hevy exercises used; \(c.templatesMerged) of them merged into \(merges.count).</p>"

        // 2. Things to check
        o += "<h2>Things to check</h2>"
        o += section("Merges", merges.count, merges.map { p in
            "<li><b>\(h(p.exercise.name))</b> ← " + p.parts.map { "\(h($0.title)) <span class=\"muted\">\($0.first)…\($0.last), \($0.workouts) wk</span>" }
                .joined(separator: " + ") + "</li>"
        })
        o += section("Renames", renames.count, renames.map { p in
            "<li>\(h(p.titles[0])) → <b>\(h(p.exercise.name))</b></li>"
        })
        let guesses = tally.guesses.values.sorted { $0.count > $1.count }
        o += section("Setting names guessed", guesses.count, guesses.map { g in
            let sample = g.lines.max { $0.value < $1.value }?.key ?? ""
            return "<li>\(h(g.exercise)): <b>\(h(g.name))</b>\(g.fallback ? " (default)" : "") ×\(g.count) <span class=\"muted\">e.g.</span> <code>\(h(sample))</code></li>"
        })
        o += section("Equipment with low confidence", doubts.count, doubts.map { p in
            "<li><b>\(h(p.exercise.name))</b>: \(h(rigText(p.exercise))) – \(h(p.rigging.doubt!))</li>"
        })
        o += section("Barbells: the bar Slam adds", barbells.count, barbells.map { p in
            let bar = p.exercise.bar.map(Format.kg) ?? "20"
            let src = p.bar?.source ?? (p.ruleBar != nil ? "rule" : "default")
            let withBar = tally.loggedWithBar[p.exercise.name].map { ", \($0) workouts already had the bar in Hevy (left as logged)" } ?? ""
            return "<li><b>\(h(p.exercise.name))</b>: \(bar) kg bar (\(src)), added from \(p.barFrom ?? "never")\(withBar)</li>"
        })
        let lr = tally.sidesOnBilateral.sorted { $0.value > $1.value }
        o += section("Left/right reps on an exercise not marked one-sided (kept as note text)", lr.count, lr.map {
            "<li>\(h($0.key)): \($0.value) workouts</li>"
        })
        let flags = gymFlags
        o += section("Gym differs from the timeline", flags.count, flags.map {
            "<li>\($0.day) \(h($0.title)): <b>\(h($0.gym))</b> (\(h($0.basis))), timeline says \(h($0.timeline))</li>"
        })
        o += section("Stacks seen at more than one gym (slots kept from the latest)", mixedStacks.count, mixedStacks.map { p in
            let gyms = p.slots.keys.map { im.finder.name($0 < 0 ? nil : $0) ?? "unknown gym" }.sorted().joined(separator: ", ")
            return "<li>\(h(p.exercise.name)): \(h(gyms))</li>"
        })

        // 3. Exercises
        o += "<h2>Exercises</h2><table class=\"cards\"><thead><tr>"
        let cols = ["Name", "Brand", "Equipment", "Stack", "Add-on", "Bar", "Sides", "One side", "Settings", "Gyms", "Workouts"]
        o += cols.map { "<th>\($0)</th>" }.joined() + "</tr></thead><tbody>"
        for p in im.plans.sorted(by: { $0.exercise.name.lowercased() < $1.exercise.name.lowercased() }) {
            let e = p.exercise
            let stack = e.stack.count == 1 ? "\(Format.kg(e.stack[0])) · 1 slot"
                : e.stack.isEmpty ? "" : "\(Format.kg(e.stack.first!))–\(Format.kg(e.stack.last!)) · \(e.stack.count) slots"
            let sides = e.rig == .barbell || e.rig == .plateLoaded ? "\(e.sides)" : ""
            let gyms = p.gyms.sorted { $0.value > $1.value }.map { "\(im.finder.name($0.key) ?? "unknown") \($0.value)" }.joined(separator: ", ")
            let cells = [h(e.name), h(e.brand), h(rigText(e)), stack, e.addOn.map(Format.kg) ?? "", e.bar.map(Format.kg) ?? "",
                         sides, e.unilateral ? "yes" : "", h(e.settings.map(\.name).joined(separator: ", ")), h(gyms), "\(workouts(p))"]
            o += "<tr>" + zip(cols, cells).map { "<td data-l=\"\($0.0)\">\($0.1)</td>" }.joined() + "</tr>"
        }
        o += "</tbody></table>"

        // 4. Samples
        o += "<h2>Sample workouts</h2>"
        for (label, w) in samples() { o += workoutCard(label, w) }

        // 5. Notes
        o += "<h2>Notes</h2>"
        o += "<p class=\"muted\">\(s.notes.lines) note lines: \(s.notes.dropped) fully turned into data or dropped, \(s.notes.kept) kept as note text (in part or whole). "
        o += "\(tally.rirUnplaced) RIR lines and \(tally.sidesUnplaced) left/right lines could not be placed on a set and stay as text.</p>"
        let kept = tally.kept.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(50)
        o += "<h3>Kept as note text (top 50 of \(tally.kept.count) distinct)</h3><table><tbody>"
        o += kept.map { "<tr><td><code>\(h($0.key))</code></td><td class=\"n\">\($0.value)</td></tr>" }.joined()
        o += "</tbody></table>"
        o += "<h3>Lines dropped, by what they held</h3><table><tbody>"
        o += tally.droppedByKind.sorted { $0.value > $1.value }
            .map { "<tr><td>\(h(Report.kindName($0.key)))</td><td class=\"n\">\($0.value)</td></tr>" }.joined()
        o += "</tbody></table>"
        o += "<h3>Unmatched loadouts (\(tally.missCount))</h3><table><tbody>"
        o += tally.misses.sorted { $0.value > $1.value }.map { "<tr><td>\(h($0.key))</td><td class=\"n\">\($0.value)</td></tr>" }.joined()
        o += "</tbody></table><ul>"
        for m in tally.missSamples(15) {
            let v = m.value.map(Format.kg) ?? "–"
            let logged = m.logged.map(Format.kg).joined(separator: ", ")
            o += "<li>\(m.day) \(h(m.exercise)): <code>\(h(m.line.trimmingCharacters(in: .whitespaces)))</code> = \(v), logged \(logged.isEmpty ? "–" : logged) <span class=\"muted\">(\(h(m.reason)), ×\(m.count))</span></li>"
        }
        o += "</ul></main></body></html>\n"
        return o
    }

    private func section(_ title: String, _ n: Int, _ items: [String]) -> String {
        "<details\(n > 0 ? " open" : "")><summary>\(h(title)) <span class=\"n\">\(n)</span></summary>"
            + (items.isEmpty ? "<p class=\"muted\">None.</p>" : "<ul>" + items.joined() + "</ul>") + "</details>"
    }

    func rigText(_ e: Exercise) -> String {
        switch e.rig {
        case .stack: "\(e.equipment.title) · stack"
        case .plateLoaded: "\(e.equipment.title) · plates, \(e.sides == 2 ? "both sides" : "one side")"
        case .barbell: "Barbell"
        case .dumbbell: "Dumbbell"
        case .plain: e.equipment.title
        }
    }

    /// The latest workout at the current gym, the latest elsewhere with gym-pin plates, and the latest with a
    /// bar other than 20 kg.
    func samples() -> [(String, Workout)] {
        let ex = Dictionary(lib.exercises.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [(String, Workout)] = []
        let here = lib.settings.gymId
        if let w = lib.workouts.first(where: { $0.gymId == here && here != nil }) {
            out.append(("Latest at \(lib.gyms.first { $0.id == here }?.name ?? "the current gym")", w))
        }
        if let w = lib.workouts.first(where: { w in
            w.gymId != here && w.exercises.contains { e in
                ex[e.exerciseId]?.rig == .stack && e.sets.contains { !($0.load?.plates.isEmpty ?? true) }
            }
        }) {
            out.append(("Gym-pin plates at \(lib.gyms.first { $0.id == w.gymId }?.name ?? "another gym")", w))
        }
        // A bar other than 20 kg, from the first bar rule when it can, in a workout not shown yet.
        let shown = Set(out.map(\.1.id))
        let first = im.rules.bars.first.map { Rx($0.name, caseless: true) }
        func odd(_ w: Workout, _ named: Bool) -> Bool {
            !shown.contains(w.id) && w.exercises.contains { e in
                guard let x = ex[e.exerciseId], x.rig == .barbell, !named || first?.matches(x.name) == true else { return false }
                return e.sets.contains { ($0.load?.base ?? 20) != 20 && ($0.load?.base ?? 0) > 0 }
            }
        }
        if let w = lib.workouts.first(where: { odd($0, true) }) ?? lib.workouts.first(where: { odd($0, false) }) {
            out.append(("A bar other than 20 kg", w))
        }
        return out
    }

    private func workoutCard(_ label: String, _ w: Workout) -> String {
        let ex = Dictionary(lib.exercises.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = TimeZone(identifier: "UTC")
        let gym = lib.gyms.first { $0.id == w.gymId }?.name ?? "no gym"
        var o = "<div class=\"workout\"><span class=\"muted\">\(h(label))</span><h3>\(h(w.title))</h3>"
        o += "<div class=\"muted\">\(f.string(from: w.start)) UTC · \(h(gym))</div>"
        if !w.notes.isEmpty { o += "<div class=\"note\">\(h(w.notes))</div>" }
        for e in w.exercises {
            guard let x = ex[e.exerciseId] else { continue }
            o += "<div class=\"ex\"><b>\(h(x.name))</b>"
            let settings = x.settings.compactMap { c in e.settings[c.id.uuidString].map { "\(c.name) \($0)" } }
            if !settings.isEmpty { o += "<div class=\"note\">\(h(settings.joined(separator: " · ")))</div>" }
            var n = 0
            for s in e.sets {
                let label: String
                switch s.kind {
                case .warmup: label = "W"
                case .drop: label = "D"
                case .normal:
                    n += 1
                    label = "\(n)"
                }
                o += "<div class=\"set\">\(h(Report.setText(s, label, x)))</div>"
            }
            if !e.note.isEmpty { o += "<div class=\"note\">\(h(e.note))</div>" }
            o += "</div>"
        }
        return o + "</div>"
    }

    /// "W 41 +2.5 × 12", "1 95 +2.5 pin 10 × 9 · RIR 2", "70 (20 5 a side) × 7", "9 / 8" for left and right.
    static func setText(_ s: WorkSet, _ label: String, _ e: Exercise) -> String {
        var parts: [String] = []
        if e.type.hasKg, let kg = s.kg {
            let rig = e.rig
            switch rig {
            case .stack, .dumbbell:
                parts.append(s.load?.summary(rig) ?? Format.kg(kg))
            case .barbell, .plateLoaded:
                if let l = s.load, let sm = l.summary(rig) {
                    parts.append(Format.kg(kg) + " (" + (l.base > 0 ? Format.kg(l.base) + " " : "") + sm + ")")
                } else {
                    parts.append(Format.kg(kg))
                }
            case .plain:
                parts.append(Format.kg(kg))
            }
        }
        var reps = ""
        if let r = s.reps {
            reps = e.unilateral ? "\(r) / \(s.repsR ?? r)" : "\(r)"
        }
        var line = label + " " + parts.joined()
        if !reps.isEmpty { line += parts.isEmpty ? reps : " × " + reps }
        if let sec = s.seconds { line += " · " + Format.clock(sec) }
        if let m = s.meters { line += " · " + Format.km(m) + " km" }
        if let r = s.rir {
            line += " · RIR " + (e.unilateral && s.rirR != nil && s.rirR != r ? "\(r) / \(s.rirR!)" : "\(r)")
        }
        return line
    }

    static func kindName(_ k: String) -> String {
        let names = [
            "L_PIN": "stack + (pin plates)", "L_SUM": "stack + extras", "L_SINGLE": "a bare number", "L_SPACED": "numbers with spaces",
            "L_COUNT": "plate counts", "L_BASE_COUNT": "dumbbell + clip-on plates", "L_PERSIDE": "plates a side",
            "L_MAX": "max + extras", "L_PLUS": "extras only", "L_DB": "dumbbell weight", "L_LEAD": "number then words",
            "L_PERSIDE_ADD": "added a side", "SIDES": "left/right reps", "SIDE1": "one side's reps", "RIR": "RIR",
            "FAIL": "fail", "EXTRA": "counters after the RIR", "SETTING": "setting", "SHOWS": "setting shown number",
            "ADJUST": "adjustment (6 down)", "LOC": "location code", "LOC_N": "location number", "POSWORD": "position words",
            "STACKS": "stack count", "CUE_NUM": "cue with a number", "PLAN": "plan",
        ]
        return names[k].map { "\($0) (\(k))" } ?? k
    }

    static let css = """
    :root{--bg:#0e1014;--card:#161a21;--line:#262c36;--text:#e7eaf0;--muted:#98a2b3;--warn:#f0b54a}
    *{box-sizing:border-box}html{-webkit-text-size-adjust:100%}
    body{margin:0;background:var(--bg);color:var(--text);font:15px/1.45 -apple-system,BlinkMacSystemFont,"Segoe UI",system-ui,sans-serif}
    main{max-width:1100px;margin:0 auto;padding:16px}
    h1{font-size:22px;margin:8px 0 4px}h2{font-size:18px;margin:28px 0 10px}h3{font-size:15px;margin:14px 0 4px}
    .muted{color:var(--muted)}.n{color:var(--warn);font-variant-numeric:tabular-nums}
    .tiles{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:8px}
    @media(min-width:700px){.tiles{grid-template-columns:repeat(6,minmax(0,1fr))}}
    .tile{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:10px 12px}
    .tile b{display:block;font-size:22px;font-variant-numeric:tabular-nums}
    details{background:var(--card);border:1px solid var(--line);border-radius:12px;margin:8px 0;padding:0 12px}
    summary{cursor:pointer;padding:12px 0;font-weight:600}
    ul{margin:0 0 12px;padding-left:18px}li{margin:5px 0;overflow-wrap:anywhere}
    table{width:100%;border-collapse:collapse;font-size:14px}td.n{white-space:nowrap;text-align:right;width:1%}
    th,td{text-align:left;padding:6px 8px;border-bottom:1px solid var(--line);vertical-align:top;overflow-wrap:anywhere}
    th{color:var(--muted);font-weight:600}
    @media(max-width:699px){
    table.cards thead{display:none}
    table.cards tr{display:block;background:var(--card);border:1px solid var(--line);border-radius:12px;margin:8px 0;padding:6px 10px}
    table.cards td{display:flex;gap:8px;border:0;padding:2px 0}
    table.cards td::before{content:attr(data-l);color:var(--muted);min-width:84px;flex:none}
    table.cards td:empty{display:none}}
    .workout{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:12px;margin:10px 0}
    .workout h3{margin:2px 0}.ex{margin:12px 0 0}.ex b{display:block}
    .set{font-variant-numeric:tabular-nums;padding-left:8px}
    .note{color:var(--muted);white-space:pre-wrap;padding-left:8px;font-size:13px;overflow-wrap:anywhere}
    code{font:13px ui-monospace,SFMono-Regular,Menlo,monospace;white-space:pre-wrap;overflow-wrap:anywhere}
    """
}

/// `s` safe inside HTML.
func h(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
}
