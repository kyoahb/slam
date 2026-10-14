import Foundation

/// A set in words, the same on the phone, in shared text and for models.
public enum SetText {
    /// "111 kg × 8", "111 kg × 8 L 7 R", "2.4 km · 12:30". `split` adds what made the weight: "80 kg (20 10 a side) × 5".
    public static func describe(_ s: WorkSet, _ ex: Exercise, split: Bool = false) -> String {
        var parts: [String] = []
        if ex.type.hasKg, let kg = s.kg {
            let made = split ? s.load?.summary(ex.rig).map { " (\($0))" } ?? "" : ""
            parts.append(Format.kg(kg) + " kg" + made)
        }
        if ex.type.hasReps {
            parts.append(ex.unilateral ? "\(s.reps ?? 0) L \(s.repsR ?? 0) R" : String(s.reps ?? 0))
        }
        var out = parts.joined(separator: " × ")
        if ex.type.hasDistance, let m = s.meters {
            out += (out.isEmpty ? "" : " · ") + (ex.type == .distanceDuration ? Format.km(m) + " km" : Format.kg(m) + " m")
        }
        if ex.type.hasTime, let t = s.seconds { out += (out.isEmpty ? "" : " · ") + Format.clock(t) }
        return out
    }

    /// " (RIR 1)", " (RIR 1 / 0)" for both sides, or nothing.
    public static func rir(_ s: WorkSet, _ ex: Exercise) -> String {
        guard ex.type.hasReps, s.kind != .warmup else { return "" }
        if ex.unilateral {
            guard s.rir != nil || s.rirR != nil else { return "" }
            return " (RIR \(s.rir.map(String.init) ?? "–") / \(s.rirR.map(String.init) ?? "–"))"
        }
        return s.rir.map { " (RIR \($0))" } ?? ""
    }
}
