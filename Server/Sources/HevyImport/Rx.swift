import Foundation

/// A regular expression with named groups, matched the way Python's `re` matches:
/// `match` is anchored where it starts, `search` looks from a position on, and both see the whole string
/// for look-behinds and for `^` and `$`.
struct Rx {
    let re: NSRegularExpression
    let names: [String]

    init(_ pattern: String, caseless: Bool = false) {
        do {
            re = try NSRegularExpression(pattern: pattern, options: caseless ? [.caseInsensitive] : [])
        } catch {
            preconditionFailure("bad pattern \(pattern): \(error)")
        }
        let groups = try! NSRegularExpression(pattern: #"\(\?<([A-Za-z][A-Za-z0-9]*)>"#)
        let p = pattern as NSString
        names = groups.matches(in: pattern, range: NSRange(location: 0, length: p.length))
            .map { p.substring(with: $0.range(at: 1)) }
    }

    /// A match starting exactly at `at`.
    func match(_ s: NSString, at: Int = 0) -> Hit? { find(s, at, .anchored) }

    /// The first match at or after `from`.
    func search(_ s: NSString, from: Int = 0) -> Hit? { find(s, from, []) }

    func matches(_ s: String) -> Bool { search(s as NSString) != nil }

    func all(_ s: NSString) -> [Hit] {
        re.matches(in: s as String, range: NSRange(location: 0, length: s.length)).map { Hit($0, s, names) }
    }

    private func find(_ s: NSString, _ from: Int, _ options: NSRegularExpression.MatchingOptions) -> Hit? {
        guard from <= s.length else { return nil }
        let opts = from > 0 ? options.union([.withTransparentBounds, .withoutAnchoringBounds]) : options
        guard let m = re.firstMatch(in: s as String, options: opts,
                                    range: NSRange(location: from, length: s.length - from)) else { return nil }
        return Hit(m, s, names)
    }
}

/// One match: its range and its named groups.
struct Hit {
    let range: NSRange
    private let s: NSString
    private let groups: [String: NSRange]

    init(_ m: NSTextCheckingResult, _ s: NSString, _ names: [String]) {
        range = m.range
        self.s = s
        var g: [String: NSRange] = [:]
        for n in names {
            let r = m.range(withName: n)
            if r.location != NSNotFound { g[n] = r }
        }
        groups = g
    }

    /// The group's text, or nil when it took no part in the match.
    subscript(_ name: String) -> String? { groups[name].map { s.substring(with: $0) } }

    var text: String { s.substring(with: range) }
    var end: Int { range.location + range.length }
}

/// Every number in `s`, in order.
func numbers(_ s: String) -> [Double] {
    Grammar.number.all(s as NSString).compactMap { Double($0.text) }
}

/// A note line in the form the patterns read: lower case, decimal commas as points, single spaces and
/// known misspellings replaced. Each unit remembers which units of the original line it came from, so
/// whatever a pattern reads can be cut out of the original and the rest kept as the note.
struct Scan {
    private(set) var units: [unichar] = []
    private var from: [Range<Int>?] = []
    private(set) var ns: NSString = ""
    /// Original units removed while normalising (object-replacement marks, currency signs).
    private(set) var dropped = IndexSet()

    init(_ raw: String, aliases: [(Rx, String)]) {
        let r = raw as NSString
        var i = 0
        while i < r.length {
            let cr = r.rangeOfComposedCharacterSequence(at: i)
            let ch = r.substring(with: cr)
            if ch == "\u{FFFC}" || ch == "£" {
                dropped.insert(integersIn: cr.location ..< cr.location + cr.length)
            } else {
                for u in ch.lowercased().utf16 {
                    units.append(u)
                    from.append(cr.location ..< cr.location + cr.length)
                }
            }
            i = cr.location + cr.length
        }
        refresh()
        trim()
        for m in Scan.decimalComma.all(ns).reversed() {
            units[m.range.location + 1] = 0x2E
        }
        refresh()
        for m in Scan.bareDecimal.all(ns).reversed() {
            replace(NSRange(location: m.range.location, length: 0), with: "0", source: from[m.range.location])
        }
        for m in Scan.spaces.all(ns).reversed() {
            replace(m.range, with: " ", source: nil)
        }
        for (rx, canonical) in aliases {
            for m in rx.all(ns).reversed() {
                replace(m.range, with: canonical, source: span(m.range))
            }
        }
    }

    var string: String { ns as String }
    var isEmpty: Bool { units.isEmpty }

    /// The original units behind `r`.
    func source(_ r: NSRange) -> IndexSet {
        var out = IndexSet()
        for i in r.location ..< r.location + r.length {
            if let s = from[i] { out.insert(integersIn: s) }
        }
        return out
    }

    /// Removes `r`, leaving one space when `space` is true, and returns the original units it stood for.
    @discardableResult
    mutating func cut(_ r: NSRange, space: Bool = true) -> IndexSet {
        let src = source(r)
        replace(r, with: space ? " " : "", source: nil)
        return src
    }

    private func span(_ r: NSRange) -> Range<Int>? {
        let s = source(r)
        guard let lo = s.first, let hi = s.last else { return nil }
        return lo ..< hi + 1
    }

    private mutating func replace(_ r: NSRange, with text: String, source: Range<Int>?) {
        let new = Array(text.utf16)
        units.replaceSubrange(r.location ..< r.location + r.length, with: new)
        from.replaceSubrange(r.location ..< r.location + r.length, with: Array(repeating: source, count: new.count))
        refresh()
    }

    private mutating func trim() {
        func blank(_ u: unichar) -> Bool {
            guard let s = Unicode.Scalar(u) else { return false }
            return CharacterSet.whitespacesAndNewlines.contains(s)
        }
        while let u = units.last, blank(u) { units.removeLast(); from.removeLast() }
        while let u = units.first, blank(u) { units.removeFirst(); from.removeFirst() }
        refresh()
    }

    private mutating func refresh() { ns = NSString(characters: units, length: units.count) }

    private static let decimalComma = Rx(#"\d,\d"#)
    private static let bareDecimal = Rx(#"(?<!\d)\.\d"#)
    private static let spaces = Rx(#"\s+"#)
}
