import Foundation
import SlamCore

/// A finished workout as plain text, for copying or sending.
enum ShareText {
    @MainActor
    static func workout(_ w: Workout, _ model: AppModel) -> String {
        var lines = [w.title.isEmpty ? "Workout" : w.title]
        var when = w.start.formatted(.dateTime.weekday(.wide).day().month(.wide).year()) + ", " + w.start.time
        if let gym = model.gym(w.gymId)?.name { when += " · " + gym }
        lines.append(when)
        var facts = [Format.duration(w.duration), Format.volume(Stats.volume(w, model.byId)), "\(Stats.sets(w)) sets"]
        let records = model.records[w.id]?.count ?? 0
        if records > 0 { facts.append(records == 1 ? "1 record" : "\(records) records") }
        lines.append(facts.joined(separator: " · "))
        if !w.notes.isEmpty { lines += ["", w.notes] }
        for e in w.exercises {
            let ex = model.byId[e.exerciseId] ?? Exercise(id: e.exerciseId, name: "Deleted exercise")
            let medals = Set(model.entryRecords(w, e).compactMap(\.setId))
            lines += ["", ex.name]
            let settings = model.settingsText(e)
            if !settings.isEmpty { lines.append(settings) }
            if !e.note.isEmpty { lines.append(e.note) }
            var n = 0
            for s in e.sets {
                let label: String
                switch s.kind {
                case .warmup: label = "Warm-up"
                case .drop: label = "Drop set"
                case .normal:
                    n += 1
                    label = "Set \(n)"
                }
                lines.append(label + ": " + SetText.describe(s, ex, split: true) + rir(s, ex) + (medals.contains(s.id) ? " 🏅" : ""))
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func rir(_ s: WorkSet, _ ex: Exercise) -> String {
        guard ex.type.hasReps, s.kind != .warmup else { return "" }
        if ex.unilateral {
            guard s.rir != nil || s.rirR != nil else { return "" }
            return " (RIR \(s.rir.map(String.init) ?? "–") / \(s.rirR.map(String.init) ?? "–"))"
        }
        return s.rir.map { " (RIR \($0))" } ?? ""
    }
}
