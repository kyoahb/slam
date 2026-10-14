import Foundation

/// A weight written out in a note: "95 +2.5 (10)", "20 5 a side", "30 + 2(0.5)".
struct Loadout {
    /// The shape it was written in; the names follow the earlier study of the notes.
    var shape: String
    /// The stack slot or dumbbell. Nil when the line gives only extras.
    var base: Double?
    var addOn: Double?
    /// Gym-pin plates, clip-on plates, or the plates on one side.
    var plates: [Double] = []
    var sides = 1
    /// What the parts add up to as written.
    var total: Double?
    /// Every weight number in the order written, the bar left out.
    var numbers: [Double] = []
    /// A bar named on the line ("; 15 bar").
    var bar: Double?
    /// "wu": the warm-ups, "wo": the working sets.
    var prefix: String?
    /// Found later in a line rather than at its start.
    var inline = false
    /// The plates were in a bracket with a pin word.
    var pinned = false

    /// Per-side shapes: the plates alone, without a bar.
    var plateTotal: Double { Double(sides) * plates.reduce(0, +) }
}

/// One piece of a note line and the original characters it was read from.
struct Frag {
    enum Value {
        case load(Loadout)
        /// "added 1.25 a side": a change with no total.
        case increment
        /// Reps on the left and right, as written.
        case sides(left: String, right: String)
        /// Reps in reserve as written: a value or a range.
        case rir(Double, Double?)
        case fail
        case setting(name: String?, value: String)
        /// "at 2 shows 9": the number the machine shows.
        case shows(name: String?, shown: String)
        /// Counters, location codes and adjustments: always dropped.
        case ignored
        /// Read so nothing else misreads it, but kept as note text.
        case text
    }

    var value: Value
    /// The name used in the audit file.
    var kind: String
    var src: IndexSet
}

/// A note line read into fragments.
struct NoteLine {
    let raw: String
    let norm: String
    var setIndex: Int?
    /// The "2:" prefix, dropped only when nothing else of the line is left.
    var prefix = IndexSet()
    var frags: [Frag] = []
    /// A plan for next time: its weights and settings are not today's.
    var plan = false
    /// What was left once every pattern had run, for the audit file.
    var rest = ""
    let dropped: IndexSet

    var loads: [(Int, Loadout)] {
        frags.indices.compactMap { i in
            if case .load(let l) = frags[i].value { return (i, l) }
            return nil
        }
    }

    /// The line with the used fragments taken out, or "" when nothing is left.
    func leftover(_ used: Set<Int>) -> String {
        var taken = IndexSet()
        for i in used { taken.formUnion(frags[i].src) }
        let body = keep(taken.union(prefix))
        // A set number alone, or with an empty "rir", is a blank template line.
        if body.isEmpty || body.lowercased() == "rir" { return "" }
        return taken.isEmpty ? raw.trimmingCharacters(in: .whitespacesAndNewlines) : keep(taken)
    }

    private func keep(_ taken: IndexSet) -> String {
        let r = raw as NSString
        var units: [unichar] = []
        for i in 0 ..< r.length where !taken.contains(i) && !dropped.contains(i) {
            units.append(r.character(at: i))
        }
        let s = String(utf16CodeUnits: units, count: units.count)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-.!?()"))
    }
}

extension Grammar {
    /// Reads one line of a note. Nil for a blank line.
    func read(_ raw: String, addOns: Set<Double>) -> NoteLine? {
        var s = Scan(raw, aliases: aliases)
        if s.isEmpty { return nil }
        var line = NoteLine(raw: raw, norm: s.string, dropped: s.dropped)
        var indexed = false
        if let m = setIndex.match(s.ns) {
            line.setIndex = m["i"].flatMap { Int($0) }
            indexed = true
            line.prefix = s.cut(m.range, space: false)
        }
        var frags: [Frag] = []

        // "3: 1-2" or a whole line "0": the effort of a working set.
        let body = s.string.trimmingCharacters(in: .whitespaces)
        if indexed || bareRirLine.match(body as NSString) != nil,
           let m = bareRir.match(s.ns), let a = Double(m["a"]!), a <= 5, bareNotLoad.match(s.ns) == nil {
            frags.append(Frag(value: .rir(a, m["b"].flatMap { Double($0) }), kind: "RIR", src: s.cut(m.range, space: false)))
        }
        if let m = onLeg.match(s.ns) {
            frags.append(Frag(value: .text, kind: "CUE_NUM", src: s.cut(m.range, space: false)))
        }
        if frags.isEmpty {
            if let found = loadout(s.string, addOns: addOns) {
                let (l, end) = found
                frags.append(Frag(value: .load(l), kind: l.shape, src: s.cut(NSRange(location: 0, length: end), space: false)))
            } else if let m = lead.match(s.ns), let v = Double(m["s"]!) {
                let tail = (s.ns.substring(from: m.end) as String).trimmingCharacters(in: .whitespaces) as NSString
                if (v >= 10 || m["s"]!.contains(".")) && leadStop.match(tail) == nil && leadLoad.match(tail) == nil {
                    let l = Loadout(shape: "L_LEAD", base: v, total: v, numbers: [v])
                    frags.append(Frag(value: .load(l), kind: "L_LEAD", src: s.cut(m.range, space: false)))
                }
            }
        }

        /// Cuts every match of `rx` that `make` accepts.
        func take(_ rx: Rx?, _ kind: String, _ make: (Hit) -> Frag.Value?) {
            guard let rx else { return }
            var pos = 0
            while let m = rx.search(s.ns, from: pos) {
                guard let v = make(m) else {
                    pos = m.end > m.range.location ? m.end : m.end + 1
                    continue
                }
                frags.append(Frag(value: v, kind: kind, src: s.cut(m.range)))
                pos = m.range.location
            }
        }
        func side(_ x: String) -> String { String(x.prefix(1)) }

        take(sides2, "SIDES") { m in
            m["as"] != m["bs"] ? Grammar.sides(m["as"]!, m["a"]!, m["bs"]!, m["b"]!) : nil
        }
        take(sides2b, "SIDES") { m in
            if let a = m["as"] {
                return a != m["bs"] ? Grammar.sides(a, m["a"]!, m["bs"]!, m["b"]!) : nil
            }
            return side(m["as2"]!) != side(m["bs2"]!) ? Grammar.sides(side(m["as2"]!), m["a2"]!, side(m["bs2"]!), m["b2"]!) : nil
        }
        take(rir, "RIR") { m in Grammar.effort(m["a"]!, m["b"]) }
        take(rirR, "RIR") { m in Grammar.effort(m["a"]!, m["b"]) }
        take(side1, "SIDE1") { _ in .text }
        take(fail, "FAIL") { _ in .fail }
        take(counters, "EXTRA") { _ in .ignored }
        for rx in keep { take(rx, "POSWORD") { _ in .text } }
        for rx in shows { take(rx, "SHOWS") { m in .shows(name: m["name"], shown: m["lab"]!) } }
        take(named, "SETTING") { m in .setting(name: m["name"], value: m["val"]!) }
        take(unnamed, "SETTING") { m in .setting(name: nil, value: m["val"] ?? m["v2"]!) }
        take(adjust, "ADJUST") { _ in .ignored }
        take(stacks, "STACKS") { _ in .text }
        take(location, "LOC") { _ in .ignored }
        if frags.contains(where: { $0.kind == "LOC" }) {
            take(locationDigit, "LOC_N") { _ in .ignored }
        }
        take(onLeg, "CUE_NUM") { _ in .text }

        // A second loadout later in the line: "lighter again, 90 (10 5)".
        if let m = inline.search(s.ns),
           plan.search((s.ns.substring(to: m.range.location) + "x") as NSString) == nil,
           let found = loadout(s.ns.substring(from: m.range.location), addOns: addOns) {
            var (l, end) = found
            l.inline = true
            frags.append(Frag(value: .load(l), kind: l.shape, src: s.cut(NSRange(location: m.range.location, length: end))))
        }
        take(perSideAdd, "L_PERSIDE_ADD") { _ in .increment }
        take(plan, "PLAN") { _ in
            line.plan = true
            return .text
        }

        line.frags = frags
        line.rest = s.string.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-.!?()"))
        return line
    }

    /// The loadout at the start of `f` and how many units it took.
    func loadout(_ f: String, addOns: Set<Double>) -> (Loadout, Int)? {
        let s = f as NSString
        func split(_ extras: [Double]) -> (Double?, [Double]) {
            let add = extras.filter { addOns.contains($0) }
            return (add.isEmpty ? nil : add.reduce(0, +), extras.filter { !addOns.contains($0) })
        }

        if f.hasPrefix("max"), let m = maxLine.match(s), m["s"] != nil || !(m["rest"] ?? "").isEmpty {
            let ex = numbers(m["rest"] ?? "")
            let (add, plates) = split(ex)
            let base = m["s"].flatMap { Double($0) }
            let l = Loadout(shape: "L_MAX", base: base, addOn: add, plates: plates, total: base.map { $0 + ex.reduce(0, +) },
                            numbers: (base.map { [$0] } ?? []) + ex)
            return (l, m.end)
        }
        if let m = perSide.match(s) {
            let per = countTerms(m["p"]!)
            let pfx = m["pfx"].map { $0 == "wu" || $0 == "warmed up with" ? "wu" : "wo" }
            let bar = m["bar"].flatMap { Double($0) }
            var l = Loadout(shape: "L_PERSIDE", base: bar, plates: per, sides: 2, numbers: per, bar: bar, prefix: pfx)
            l.total = l.plateTotal + (bar ?? 0)
            return (l, m.end)
        }
        if let m = barLine.match(s) {
            let per = numbers(m["p"]!)
            let bar = Double(m["bar"]!)!
            var l = Loadout(shape: "L_PERSIDE", base: bar, plates: per, sides: 2, numbers: per, bar: bar)
            l.total = l.plateTotal + bar
            return (l, m.end)
        }
        if digitParen.match(s) == nil, let m = pin.match(s) {
            let base = Double(m["s"]!)!
            let add = m["a"].flatMap { Double($0) }
            let plates = numbers(m["p"]!.replacingOccurrences(of: "[a-z]", with: "", options: .regularExpression))
            let pinned = m["pin"] != nil || m["pin2"] != nil
            let l = Loadout(shape: "L_PIN", base: base, addOn: add, plates: plates,
                            total: base + (add ?? 0) + plates.reduce(0, +),
                            numbers: [base] + (add.map { [$0] } ?? []) + plates, pinned: pinned)
            return (l, m.end)
        }
        if let m = pinLoose.match(s) {
            if let sv = m["s"], let base = Double(sv) {
                let vals = numbers(m["rest"] ?? "")
                let (add, plates) = split(vals)
                return (Loadout(shape: "L_PIN", base: base, addOn: add, plates: plates, total: base + vals.reduce(0, +),
                                numbers: [base] + vals, pinned: true), m.end)
            }
            if let sv = m["s2"], let base = Double(sv), let p = Double(m["p2"]!) {
                return (Loadout(shape: "L_PIN", base: base, plates: [p], total: base + p, numbers: [base, p], pinned: true), m.end)
            }
            let base = Double(m["s3"]!)!
            let ex = numbers(m["rest3"] ?? "")
            let p = numbers(m["p3"]!)
            let (add, plates) = split(ex)
            return (Loadout(shape: "L_PIN", base: base, addOn: add, plates: plates + p,
                            total: base + ex.reduce(0, +) + p.reduce(0, +), numbers: [base] + ex + p, pinned: true), m.end)
        }
        if let m = db.match(s) {
            if let dv = m["d"], let d = Double(dv) {
                let x = m["x"].flatMap { Double($0) }
                return (Loadout(shape: "L_DB", base: d, plates: x.map { [$0] } ?? [], total: d + (x ?? 0),
                                numbers: [d] + (x.map { [$0] } ?? [])), m.end)
            }
            let d = Double(m["d2"]!)!
            return (Loadout(shape: "L_DB", base: d, total: d, numbers: [d]), m.end)
        }
        if let m = count.match(s), countParen.search(m["p"]! as NSString) != nil {
            let terms = m["p"]!
            if let lead = countLead.match(terms as NSString), let b = Double(lead["b"]!), b > 5 {
                let pl = countTerms((terms as NSString).substring(from: lead.end))
                return (Loadout(shape: "L_BASE_COUNT", base: b, plates: pl, total: b + pl.reduce(0, +), numbers: [b] + pl), m.end)
            }
            let pl = countTerms(terms)
            return (Loadout(shape: "L_COUNT", plates: pl, total: pl.reduce(0, +), numbers: pl), m.end)
        }
        if let m = sum.match(s) {
            let base = Double(m["s"]!)!
            let ex = numbers(m["rest"]!)
            let (add, plates) = split(ex)
            let pinned = pinWord.matches(m.text)
            return (Loadout(shape: "L_SUM", base: base, addOn: add, plates: plates, total: base + ex.reduce(0, +),
                            numbers: [base] + ex, pinned: pinned), m.end)
        }
        if let m = plus.match(s) {
            let ex = numbers(m["rest"]!)
            let (add, plates) = split(ex)
            return (Loadout(shape: "L_PLUS", addOn: add, plates: plates, numbers: ex), m.end)
        }
        if let m = spaced.match(s) {
            let vals = [Double(m["s"]!)!] + numbers(m["rest"]!)
            let (add, plates) = split(Array(vals.dropFirst()))
            return (Loadout(shape: "L_SPACED", base: vals[0], addOn: add, plates: plates, total: vals.reduce(0, +),
                            numbers: vals, pinned: m["pin"] != nil), m.end)
        }
        if let m = single.match(s), let v = Double(m["s"]!) {
            return (Loadout(shape: "L_SINGLE", base: v, total: v, numbers: [v]), m.end)
        }
        return nil
    }

    /// "4(25) + 2(15) + 5" as plates, the counts written out.
    func countTerms(_ s: String) -> [Double] {
        var out: [Double] = []
        for m in countTerm.all(s as NSString) {
            if let c = m["c"], let n = Int(c) {
                for _ in 0 ..< n { out += numbers(m["cp"]!) }
            } else if let x = m["x"], let n = Int(x), let p = Double(m["xp"]!) {
                out += Array(repeating: p, count: n)
            } else if let v = m["n"].flatMap({ Double($0) }) {
                out.append(v)
            }
        }
        return out
    }

    static func sides(_ a: String, _ av: String, _ b: String, _ bv: String) -> Frag.Value {
        a == "l" ? .sides(left: av, right: bv) : .sides(left: bv, right: av)
    }

    static func effort(_ a: String, _ b: String?) -> Frag.Value? {
        if a.contains("/") {
            let p = a.split(separator: "/").compactMap { Double($0) }
            guard p.count == 2, p[1] != 0 else { return nil }
            return .rir(p[0] / p[1], nil)
        }
        guard let v = Double(a) else { return nil }
        return .rir(v, b.flatMap { Double($0) })
    }
}

extension Frag.Value {
    /// Slam keeps whole RIR: the top of a range, halves rounded up, nothing below 0.
    static func rirValue(_ a: Double, _ b: Double?) -> Int {
        Int(Swift.max(0, (b ?? a)).rounded(.up))
    }
}
