import Foundation

/// Counts kept while the sets are read, for the dry-run report.
struct Tally {
    struct Miss {
        var reason: String
        var day: String
        var exercise: String
        var line: String
        var value: Double?
        var logged: [Double]
        var count = 1
    }

    struct Guess {
        var exercise: String
        var name: String
        /// No other line of the exercise names a setting, so the default name was used.
        var fallback: Bool
        var count = 0
        var lines: [String: Int] = [:]
    }

    /// One workout note line as read, for checking the parser against the earlier study.
    struct AuditLine: Encodable {
        var date: String
        var ex: String
        var raw: String
        var setidx: Int?
        var kinds: [String]
        var rest: String
        var kept: String
    }

    var loadouts = 0
    var matched = 0
    /// A bare number that only repeats the logged weight.
    var restated = 0
    /// Loadouts on plan lines, not today's weight.
    var planned = 0
    var misses: [String: Int] = [:]
    var missOrder: [String] = []
    var missLines: [String: Miss] = [:]

    var lines = 0
    var dropped = 0
    var kept: [String: Int] = [:]
    var droppedByKind: [String: Int] = [:]
    var usedByKind: [String: Int] = [:]
    var guesses: [String: Guess] = [:]
    var sidesUnplaced = 0
    var rirUnplaced = 0
    var sidesOnBilateral: [String: Int] = [:]
    var loggedWithBar: [String: Int] = [:]
    var audit: [AuditLine] = []

    mutating func miss(_ reason: String, day: String, exercise: String, line: String, value: Double?, logged: [Double]) {
        misses[reason, default: 0] += 1
        let key = exercise + "\u{1}" + line.trimmingCharacters(in: .whitespaces)
        if missLines[key] == nil {
            missOrder.append(key)
            missLines[key] = Miss(reason: reason, day: day, exercise: exercise, line: line, value: value, logged: logged)
        } else {
            missLines[key]!.count += 1
            missLines[key]!.day = day
        }
    }

    mutating func guess(_ exercise: String, _ name: String, _ line: String, guessed: Bool) {
        let key = exercise + "\u{1}" + name
        var g = guesses[key] ?? Guess(exercise: exercise, name: name, fallback: !guessed)
        g.count += 1
        g.lines[line.trimmingCharacters(in: .whitespaces), default: 0] += 1
        guesses[key] = g
    }

    mutating func count(_ line: NoteLine, left: String, used: Set<Int>, day: String, exercise: String) {
        lines += 1
        if left.isEmpty {
            dropped += 1
            for k in Set(line.frags.map(\.kind)) { droppedByKind[k, default: 0] += 1 }
        } else {
            kept[left, default: 0] += 1
        }
        for i in used { usedByKind[line.frags[i].kind, default: 0] += 1 }
        audit.append(AuditLine(date: day, ex: exercise, raw: line.raw, setidx: line.setIndex,
                               kinds: line.frags.map(\.kind), rest: line.rest, kept: left))
    }

    var missCount: Int { misses.values.reduce(0, +) }

    /// Up to `n` unmatched lines, taken in turn from each reason, most frequent reason first.
    func missSamples(_ n: Int) -> [Miss] {
        let all = missOrder.map { missLines[$0]! }
        let reasons = misses.sorted { $0.value > $1.value }.map(\.key)
        var byReason = Dictionary(grouping: all, by: \.reason).mapValues { $0.sorted { $0.count > $1.count } }
        var out: [Miss] = []
        while out.count < n && byReason.values.contains(where: { !$0.isEmpty }) {
            for r in reasons where out.count < n {
                if let m = byReason[r]?.first {
                    out.append(m)
                    byReason[r]!.removeFirst()
                }
            }
        }
        return out
    }
}
