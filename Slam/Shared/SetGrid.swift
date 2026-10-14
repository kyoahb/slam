import SwiftUI
import SlamCore

/// A finished exercise's sets, read only, in the same columns as the workout screen.
/// The tick column shows a medal on sets that set a record.
struct SetGrid: View {
    let entry: WorkoutExercise
    let exercise: Exercise
    var records: [Record] = []

    var body: some View {
        let type = exercise.type
        let two = exercise.unilateral && type.hasReps
        let labels = Previous.labels(entry.sets)
        let medals = Set(records.compactMap(\.setId))
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("SET").frame(width: 40)
                if type.hasKg { Text("KG").frame(maxWidth: .infinity) }
                if type.hasReps {
                    RepsHeader(title: two ? "LEFT" : "REPS")
                    if two { RepsHeader(title: "RIGHT") }
                }
                if type.hasDistance { Text(type == .distanceDuration ? "KM" : "M").frame(maxWidth: .infinity) }
                if type.hasTime { Text("TIME").frame(maxWidth: .infinity) }
                Color.clear.frame(width: 28, height: 1)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.grey)
            .padding(.bottom, 2)
            ForEach(Array(entry.sets.enumerated()), id: \.element.id) { i, s in
                HStack(spacing: 6) {
                    Text(labels[i])
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.kindColor(s.kind))
                        .frame(width: 40)
                    if type.hasKg {
                        WeightLabel(main: s.shownKg(exercise.rig).map { Format.kg($0) } ?? "–", load: s.load,
                                    rig: exercise.rig, size: 16)
                            .frame(maxWidth: .infinity)
                    }
                    if type.hasReps {
                        reps(s.reps, s.rir, warm: s.kind == .warmup, tone: two ? Theme.left : .clear)
                        if two { reps(s.repsR, s.rirR, warm: s.kind == .warmup, tone: Theme.right) }
                    }
                    if type.hasDistance {
                        value(s.meters.map { type == .distanceDuration ? Format.km($0) : Format.kg($0) })
                    }
                    if type.hasTime { value(s.seconds.map { Format.clock($0) }) }
                    Image(systemName: "medal.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.medal)
                        .opacity(medals.contains(s.id) ? 1 : 0)
                        .frame(width: 28)
                }
                .frame(minHeight: 34)
            }
        }
    }

    private func value(_ text: String?) -> some View {
        Text(text ?? "–")
            .font(.system(size: 16, weight: .semibold))
            .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity)
    }

    private func reps(_ reps: Int?, _ rir: Int?, warm: Bool, tone: Color) -> some View {
        RepsSplit(reps: reps.map { String($0) } ?? "–", rir: warm ? nil : .some(rir), size: 16)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(RoundedRectangle(cornerRadius: 8).fill(tone))
    }
}

/// A weight the way it was loaded: a slot or dumbbell with what went on top ("109 +2 +5"),
/// or a total with its plates under it ("80" over "20 10 a side").
struct WeightLabel: View {
    let main: String
    let load: Load?
    let rig: Rig
    var dim = false
    var size: CGFloat = 17

    var body: some View {
        Group {
            switch rig {
            case .stack, .dumbbell:
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    number
                    if let a = load?.addOn, a > 0 { badge("+" + Format.kg(a), Theme.blue) }
                    if let l = load, !l.plates.isEmpty { badge("+" + Format.kg(l.plateWeight), Theme.plate) }
                }
            case .barbell, .plateLoaded:
                VStack(spacing: 0) {
                    number
                    if let parts = load?.summary(rig) {
                        Text(parts)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.plate.opacity(dim ? 0.5 : 1))
                    }
                }
            case .plain:
                number
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private var number: some View {
        Text(main.isEmpty ? " " : main)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(dim ? Theme.dim : .white)
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: size - 5, weight: .bold))
            .foregroundStyle(color.opacity(dim ? 0.5 : 1))
    }
}

/// What the Apple Watch measured for a linked cardio exercise: "32:10 · 6.2 km · 412 kcal · 141 bpm".
struct WatchLine: View {
    let link: WatchLink

    var body: some View {
        var parts = [Format.clock(link.seconds)]
        if let m = link.meters { parts.append(Format.km(m) + " km") }
        if let k = link.kcal { parts.append("\(Int(k.rounded())) kcal") }
        if let h = link.heartRate { parts.append("\(Int(h.rounded())) bpm") }
        return Label(parts.joined(separator: " · "), systemImage: "applewatch")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.green)
            .monospacedDigit()
    }
}

/// "REPS · RIR", with RIR in its colour.
struct RepsHeader: View {
    let title: String

    var body: some View {
        Text("\(title) \(Text("· RIR").foregroundStyle(Theme.rir))")
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
    }
}

/// Reps | RIR in one cell. `rir` nil: no RIR part at all (warm-ups); `.some(nil)`: a dash.
struct RepsSplit: View {
    let reps: String
    let rir: Int??
    var repsDim = false
    var rirDim = false
    var size: CGFloat = 17

    var body: some View {
        HStack(spacing: 7) {
            Text(reps)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(repsDim ? Theme.dim : .white)
            if let rir {
                Rectangle().fill(Theme.control).frame(width: 1, height: size + 2)
                Text(rir.map { String($0) } ?? "–")
                    .font(.system(size: size - 2, weight: .bold))
                    .foregroundStyle(rir == nil ? Theme.dim : Theme.rir.opacity(rirDim ? 0.45 : 1))
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

/// Stronger or weaker than last time, set by set.
struct TrendBadge: View {
    let trend: Trend

    private var style: (icon: String, text: String, color: Color) {
        switch trend {
        case .up: ("arrow.up.right", "Stronger", Theme.green)
        case .down: ("arrow.down.right", "Weaker", Theme.red)
        case .same: ("equal", "Same", Theme.grey)
        }
    }

    var body: some View {
        let (icon, text, color) = style
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .labelStyle(.titleAndIcon)
    }
}

/// "Heaviest Weight · Best Set 2", under an exercise that set records.
struct RecordLine: View {
    let records: [Record]

    var body: some View {
        if !records.isEmpty {
            Label(records.map(\.kind.title).joined(separator: " · "), systemImage: "medal.fill")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.medal)
        }
    }
}

extension AppModel {
    /// The records one entry of a workout set.
    func entryRecords(_ w: Workout, _ e: WorkoutExercise) -> [Record] {
        let ids = Set(e.sets.map(\.id))
        return (records[w.id] ?? []).filter { r in
            r.setId.map(ids.contains) ?? (r.exerciseId == e.exerciseId)
        }
    }

    func trend(_ w: Workout, _ e: WorkoutExercise) -> Trend? {
        guard let type = byId[e.exerciseId]?.type else { return nil }
        return Trend.compare(e, last: lastTime(e.exerciseId, excluding: w.id, before: w.start), type: type)
    }

    /// Machine settings as "Seat 3 · Pad 4".
    func settingsText(_ e: WorkoutExercise) -> String {
        (byId[e.exerciseId]?.settings ?? []).compactMap { c in
            let v = e[setting: c.id]
            return v.isEmpty ? nil : "\(c.name) \(v)"
        }
        .joined(separator: " · ")
    }
}
