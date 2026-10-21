import SwiftUI
import SlamCore

/// One exercise in a workout or routine: notes, machine settings, the set table, Add Set.
struct ExerciseCard: View {
    @Environment(AppModel.self) private var model
    @Bindable var editor: WorkoutEditor
    let entry: WorkoutExercise
    @FocusState private var noteFocused: Bool

    private var exercise: Exercise { editor.exercise(entry) }

    var body: some View {
        let ex = exercise
        let placeholders = editor.placeholders(entry)
        let labels = Previous.labels(entry.sets)
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Button { editor.historyFor = ExerciseLink(id: entry.exerciseId) } label: {
                        HStack(spacing: 10) {
                            Thumb(exercise: ex, size: 40)
                            Text(ex.name)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Theme.blue)
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 4)
                    menu
                }
                let long = editor.longNote(entry)
                if !long.isEmpty {
                    Text(long).font(.subheadline).foregroundStyle(.white)
                }
                settingsLine(ex)
                if let link = entry.watch { WatchLine(link: link) }
                noteField
            }
            .padding(.horizontal, 16)

            SetTable(editor: editor, entry: entry, exercise: ex, placeholders: placeholders, labels: labels)

            Button { editor.addSet(entry.id) } label: {
                Label("Add Set", systemImage: "plus")
            }
            .buttonStyle(FillButton(fill: Theme.surface, height: 36))
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 14)
        .onChange(of: noteFocused) { _, focused in
            if focused { editor.select(nil) }
        }
    }

    private var menu: some View {
        Menu {
            Button("Reorder Exercises", systemImage: "arrow.up.arrow.down") { editor.reordering = true }
            Button("Replace Exercise", systemImage: "arrow.triangle.2.circlepath") { editor.replacing = EntryRef(id: entry.id) }
            Button("Machine Settings", systemImage: "slider.horizontal.3") { editor.settingsFor = EntryRef(id: entry.id) }
            Button("Edit Exercise", systemImage: "pencil") { editor.editingExercise = ExerciseLink(id: entry.exerciseId) }
            Button("Remove Exercise", systemImage: "xmark", role: .destructive) { editor.remove(entry.id) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 32)
                .contentShape(Rectangle())
        }
    }

    @ViewBuilder
    private func settingsLine(_ ex: Exercise) -> some View {
        let shown = ex.settings.filter { editor.mode != .routine || !$0.perWorkout }
        if !shown.isEmpty {
            Button { editor.settingsFor = EntryRef(id: entry.id) } label: {
                Text(settingsText(shown))
                    .font(.subheadline)
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
        }
    }

    private func settingsText(_ list: [Configurable]) -> AttributedString {
        var out = AttributedString()
        for (i, c) in list.enumerated() {
            if i > 0 {
                var sep = AttributedString("  ·  ")
                sep.foregroundColor = Theme.dim
                out += sep
            }
            var name = AttributedString(c.name + " ")
            name.foregroundColor = Theme.grey
            let value = entry[setting: c.id]
            var shown = AttributedString(value.isEmpty ? "–" : value)
            shown.foregroundColor = Color.white
            shown.font = Font.subheadline.weight(.semibold)
            out += name + shown
        }
        return out
    }

    private var noteField: some View {
        let lastNote = editor.mode == .routine ? "" : (editor.last(entry)?.note ?? "")
        let prompt = editor.mode == .routine ? "Add routine notes here" : (lastNote.isEmpty ? "Add notes here..." : lastNote)
        return TextField("", text: Binding(get: { entry.note }, set: { editor.setNote(entry.id, $0) }),
                         prompt: Text(prompt).foregroundColor(Theme.dim), axis: .vertical)
            .font(.subheadline)
            .focused($noteFocused)
    }
}

struct SetTable: View {
    @Bindable var editor: WorkoutEditor
    let entry: WorkoutExercise
    let exercise: Exercise
    let placeholders: [WorkSet?]
    let labels: [String]

    var body: some View {
        let type = exercise.type
        let two = exercise.unilateral && type.hasReps
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("SET").frame(width: 40)
                if type.hasKg { Text(type.kgSign + "KG").frame(maxWidth: .infinity) }
                if type.hasReps {
                    RepsHeader(title: two ? "LEFT" : "REPS")
                    if two { RepsHeader(title: "RIGHT") }
                }
                if type.hasDistance { Text(type == .distanceDuration ? "KM" : "M").frame(maxWidth: .infinity) }
                if type.hasTime { Text("TIME").frame(maxWidth: .infinity) }
                if editor.showsTicks { Image(systemName: "checkmark").frame(width: 44) }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.grey)
            .padding(.horizontal, 16)
            .padding(.bottom, 4)

            ForEach(Array(entry.sets.enumerated()), id: \.element.id) { i, set in
                SetRow(editor: editor, entry: entry, exercise: exercise, set: set, label: labels[i],
                       placeholder: placeholders[i])
                    .id(set.id)
            }
        }
    }
}

struct SetRow: View {
    @Bindable var editor: WorkoutEditor
    let entry: WorkoutExercise
    let exercise: Exercise
    let set: WorkSet
    let label: String
    let placeholder: WorkSet?

    var body: some View {
        let type = exercise.type
        let two = exercise.unilateral && type.hasReps
        let ref = SetRef(entry: entry.id, set: set.id)
        HStack(spacing: 6) {
            Menu {
                Button { editor.setKind(ref, .warmup) } label: { Label("Warm Up Set", systemImage: "w.square") }
                Button { editor.setKind(ref, .normal) } label: { Label("Normal Set", systemImage: "1.square") }
                Button { editor.setKind(ref, .drop) } label: { Label("Drop Set", systemImage: "d.square") }
                Button(role: .destructive) { editor.removeSet(ref) } label: { Label("Remove Set", systemImage: "xmark") }
            } label: {
                Text(label)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.kindColor(set.kind))
                    .frame(width: 40, height: 40)
                    .overlay(alignment: .topTrailing) {
                        if editor.hasRecord(entry.id, set.id) {
                            Image(systemName: "medal.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.medal)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .contentShape(Rectangle())
            }
            .animation(.spring(duration: 0.35, bounce: 0.5), value: editor.hasRecord(entry.id, set.id))
            if type.hasKg { valueCell(.kg) }
            if type.hasReps {
                repsCell(.reps, tone: two ? Theme.left : .clear)
                if two { repsCell(.repsR, tone: Theme.right) }
            }
            if type.hasDistance { valueCell(.distance) }
            if type.hasTime { valueCell(.time) }
            if editor.showsTicks {
                HoldTick(done: set.done) { editor.toggleDone(entry.id, set.id) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
        .background(set.done && editor.showsTicks ? Theme.doneRow : .clear)
    }

    private func cell(_ field: Field) -> Cell { Cell(entry: entry.id, set: set.id, field: field) }

    /// A value; the weight is always the total, its parts are set in the keypad.
    private func valueCell(_ field: Field) -> some View {
        let c = cell(field)
        let focused = editor.focus == c
        let typed = editor.text(c)
        let shown = typed ?? editor.placeholderText(c) ?? "–"
        return Button { editor.select(c) } label: {
            Text(shown.isEmpty ? " " : shown)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(typed == nil ? Theme.dim : .white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(RoundedRectangle(cornerRadius: 8).fill(focused ? Theme.control : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Reps, then RIR in its own colour, split by a thin line. Warm-ups have no RIR.
    private func repsCell(_ field: Field, tone: Color) -> some View {
        let c = cell(field)
        let focused = editor.focus == c
        let typed = editor.text(c)
        let reps = typed ?? editor.placeholderText(c) ?? "–"
        let rir = field == .repsR ? set.rirR : set.rir
        let rirPlaceholder = field == .repsR ? placeholder?.rirR : placeholder?.rir
        return Button { editor.select(c) } label: {
            RepsSplit(reps: reps.isEmpty ? " " : reps, rir: set.kind == .warmup ? nil : .some(rir ?? rirPlaceholder),
                      repsDim: typed == nil, rirDim: rir == nil, size: 17)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(RoundedRectangle(cornerRadius: 8).fill(focused ? Theme.control : tone))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The tick, held for half a second to finish or reopen a set, so a brush while pocketing the phone does nothing.
struct HoldTick: View {
    let done: Bool
    let action: () -> Void
    @State private var fill: CGFloat = 0

    static let hold = 0.5

    var body: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(done ? Theme.green : Theme.control)
            .overlay(alignment: .leading) {
                GeometryReader { g in
                    Rectangle().fill(done ? Theme.control : Theme.green).frame(width: g.size.width * fill)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay {
                Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
            }
            .frame(width: 34, height: 28)
            .frame(width: 44, height: 40)
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: Self.hold, maximumDistance: 16) {
                var instant = Transaction()
                instant.disablesAnimations = true
                withTransaction(instant) { fill = 0 }
                action()
            } onPressingChanged: { pressing in
                withAnimation(pressing ? .linear(duration: Self.hold) : .easeOut(duration: 0.15)) { fill = pressing ? 1 : 0 }
            }
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(done ? "Untick set" : "Tick set")
            .accessibilityAction { action() }
    }
}
