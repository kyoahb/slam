import SwiftUI
import PhotosUI
import SlamCore

/// Search plus equipment and muscle filters, shared by the picker and the Exercises page.
struct ExerciseFilter {
    var search = ""
    var equipment: Equipment?
    var muscle: Muscle?

    var isEmpty: Bool { search.isEmpty && equipment == nil && muscle == nil }

    func apply(_ list: [Exercise]) -> [Exercise] {
        let words = search.lowercased().split(separator: " ")
        return list.filter { e in
            (equipment == nil || e.equipment == equipment)
                && (muscle == nil || e.primary == muscle || e.secondary.contains(muscle!))
                && words.allSatisfy { e.name.lowercased().contains($0) || e.brand.lowercased().contains($0) }
        }
    }
}

struct FilterBar: View {
    @Binding var filter: ExerciseFilter

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                Button("All Equipment") { filter.equipment = nil }
                ForEach(Equipment.allCases, id: \.self) { e in
                    Button(e.title) { filter.equipment = e }
                }
            } label: {
                Text(filter.equipment?.title ?? "All Equipment")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(filter.equipment == nil ? .white : Theme.blue)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
            }
            Menu {
                Button("All Muscles") { filter.muscle = nil }
                ForEach(Muscle.allCases, id: \.self) { m in
                    Button(m.title) { filter.muscle = m }
                }
            } label: {
                Text(filter.muscle?.title ?? "All Muscles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(filter.muscle == nil ? .white : Theme.blue)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

struct ExerciseRow: View {
    let exercise: Exercise
    var selected = false

    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(selected ? Theme.blue : .clear).frame(width: 4)
            Thumb(exercise: exercise, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(exercise.name).font(.body).foregroundStyle(.white).lineLimit(2)
                HStack(spacing: 6) {
                    Text(exercise.primary.title).font(.subheadline).foregroundStyle(Theme.grey)
                    if !exercise.brand.isEmpty { Tag(text: exercise.brand) }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .padding(.trailing, 16)
        .contentShape(Rectangle())
    }
}

struct ExercisePicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var single = false
    let onAdd: ([Exercise]) -> Void
    @State private var filter = ExerciseFilter()
    @State private var selected: [UUID] = []
    @State private var creating = false

    var body: some View {
        NavigationStack {
            List {
                let all = filter.apply(model.exercises).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                if filter.isEmpty {
                    let recent = model.recentExerciseIds.compactMap { model.byId[$0] }
                    if !recent.isEmpty {
                        Section("Recent Exercises") {
                            ForEach(recent) { row($0) }
                        }
                    }
                }
                Section(filter.isEmpty ? "All Exercises" : "\(all.count) found") {
                    ForEach(all) { row($0) }
                    if all.isEmpty {
                        Button { creating = true } label: {
                            Label(filter.search.isEmpty ? "Create Exercise" : "Create \u{201C}\(filter.search)\u{201D}",
                                  systemImage: "plus")
                                .foregroundStyle(Theme.blue)
                                .padding(.vertical, 10)
                        }
                        .listRowBackground(Theme.bg)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .searchable(text: $filter.search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search exercise")
            .safeAreaInset(edge: .top, spacing: 0) { FilterBar(filter: $filter).background(Theme.bg) }
            .safeAreaInset(edge: .bottom) {
                if !selected.isEmpty && !single {
                    Button(selected.count == 1 ? "Add exercise" : "Add \(selected.count) exercises") {
                        onAdd(selected.compactMap { model.byId[$0] })
                        dismiss()
                    }
                    .buttonStyle(FillButton(fill: Theme.blue))
                    .padding(16)
                }
            }
            .navigationTitle(single ? "Replace Exercise" : "Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button("Create") { creating = true } }
            }
            .sheet(isPresented: $creating) {
                NavigationStack {
                    ExerciseForm(exercise: Exercise(name: filter.search), isNew: true) { e in
                        model.save(exercise: e)
                        if single {
                            onAdd([e])
                            dismiss()
                        } else {
                            selected.append(e.id)
                        }
                    }
                }
                .environment(model)
            }
        }
    }

    private func row(_ e: Exercise) -> some View {
        Button {
            if single {
                onAdd([e])
                dismiss()
            } else if let i = selected.firstIndex(of: e.id) {
                selected.remove(at: i)
            } else {
                selected.append(e.id)
            }
        } label: {
            ExerciseRow(exercise: e, selected: selected.contains(e.id))
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Theme.bg)
        .listRowSeparatorTint(Theme.line)
    }
}

/// Create or edit an exercise. Hevy's fields plus L/R, how its weight is loaded, brand and machine settings.
struct ExerciseForm: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var exercise: Exercise
    let isNew: Bool
    let onSave: (Exercise) -> Void
    @State private var item: PhotosPickerItem?

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    PhotosPicker(selection: $item, matching: .images) {
                        VStack(spacing: 6) {
                            if let file = exercise.photo, let image = model.thumbnail(file) {
                                Image(uiImage: image).resizable().scaledToFill()
                                    .frame(width: 84, height: 84).clipShape(Circle())
                            } else {
                                Image(systemName: "camera")
                                    .font(.title2)
                                    .frame(width: 84, height: 84)
                                    .background(Circle().fill(Theme.control))
                            }
                            Text(exercise.photo == nil ? "Add Photo" : "Change Photo").font(.footnote)
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
            Section {
                TextField("Exercise Name", text: $exercise.name)
                TextField("Brand (Precor, Matrix…)", text: $exercise.brand)
                Picker("Equipment", selection: $exercise.equipment) {
                    ForEach(Equipment.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Primary Muscle Group", selection: $exercise.primary) {
                    ForEach(Muscle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                NavigationLink {
                    MusclePicker(selected: $exercise.secondary)
                } label: {
                    HStack {
                        Text("Other Muscles")
                        Spacer()
                        Text(exercise.secondary.isEmpty ? "Optional" : exercise.secondary.map(\.title).joined(separator: ", "))
                            .foregroundStyle(Theme.grey)
                            .lineLimit(1)
                    }
                }
                Picker("Exercise Type", selection: $exercise.type) {
                    ForEach(ExerciseType.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if exercise.type.hasReps {
                    Toggle("Left and Right Separately", isOn: $exercise.unilateral)
                }
            }
            weightSection
            Section("Settings") {
                ForEach($exercise.settings) { $c in
                    HStack {
                        TextField("Seat, Pad, Incline…", text: $c.name)
                        Picker("", selection: $c.perWorkout) {
                            Text("Per routine").tag(false)
                            Text("Each workout").tag(true)
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                .onDelete { exercise.settings.remove(atOffsets: $0) }
                Button("Add Setting", systemImage: "plus") {
                    exercise.settings.append(Configurable(name: ""))
                }
            }
            if !isNew && model.uses(exercise.id) == 0 {
                Section {
                    Button("Delete Exercise", role: .destructive) {
                        model.delete(exercise: exercise)
                        dismiss()
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle(isNew ? "Create Exercise" : "Edit Exercise")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    var e = exercise
                    e.name = e.name.trimmingCharacters(in: .whitespaces)
                    e.brand = e.brand.trimmingCharacters(in: .whitespaces)
                    e.settings = e.settings.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
                    if !e.type.hasReps { e.unilateral = false }
                    // Only what this equipment uses is kept.
                    if e.equipment != .machine { e.plateSides = 0 }
                    if e.rig != .stack || (e.addOn ?? 0) <= 0 { e.addOn = nil }
                    if e.rig != .stack { e.stack = [] }
                    if e.rig != .barbell && e.rig != .plateLoaded { e.bar = nil }
                    onSave(e)
                    dismiss()
                }
                .disabled(exercise.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: item) { _, picked in
            guard let picked else { return }
            Task {
                if let data = try? await picked.loadTransferable(type: Data.self), let p = model.addPhoto(data) {
                    exercise.photo = p.file
                }
                item = nil
            }
        }
    }
}

extension ExerciseForm {
    /// A stack machine: its slots and add-on. Plate loaded: the sides and the machine's own weight. A barbell: the bar.
    @ViewBuilder
    private var weightSection: some View {
        if exercise.type.hasKg && [.machine, .cable, .barbell].contains(exercise.equipment) {
            Section {
                if exercise.equipment == .machine {
                    Toggle("Plate Loaded", isOn: Binding(get: { exercise.plateSides > 0 },
                                                         set: { exercise.plateSides = $0 ? 2 : 0 }))
                }
                switch exercise.rig {
                case .stack:
                    NavigationLink {
                        StackEditor(stack: $exercise.stack)
                    } label: {
                        HStack {
                            Text("Weight Stack")
                            Spacer()
                            Text(stackSummary).foregroundStyle(Theme.grey)
                        }
                    }
                    KgField(title: "Add-on Weight", value: $exercise.addOn, placeholder: "None")
                case .plateLoaded:
                    Picker("Plates Go On", selection: $exercise.plateSides) {
                        Text("Both Sides").tag(2)
                        Text("One Side").tag(1)
                    }
                    KgField(title: "Machine Weight", value: $exercise.bar, placeholder: "0")
                case .barbell:
                    KgField(title: "Bar Weight", value: $exercise.bar, placeholder: "20")
                default:
                    EmptyView()
                }
            }
        }
    }

    private var stackSummary: String {
        guard let first = exercise.stack.first, let last = exercise.stack.last else { return "Any weight" }
        return "\(Format.kg(first))–\(Format.kg(last)) kg · \(exercise.stack.count)"
    }
}

/// A weight typed into a form row. Text, not a number format, so it is kept as it is typed.
struct KgField: View {
    let title: String
    @Binding var value: Double?
    let placeholder: String
    @State private var text = ""

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField(placeholder, text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text("kg").foregroundStyle(Theme.grey)
        }
        .onAppear { text = value.map { Format.kg($0) } ?? "" }
        .onChange(of: text) { _, t in value = Double(t.replacingOccurrences(of: ",", with: ".")) }
    }
}

/// The weights a machine's stack can be pinned at: filled in steps, then single slots added or removed.
struct StackEditor: View {
    @Binding var stack: [Double]
    @State private var from = ""
    @State private var step = ""
    @State private var to = ""
    @State private var extra = ""
    @FocusState private var typing: Bool

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    number("From", $from)
                    number("Step", $step)
                    number("To", $to)
                }
                Button("Fill Slots") {
                    stack = filled
                    typing = false
                }
                .disabled(filled.isEmpty)
            }
            Section(stack.isEmpty ? "Any weight" : "\(stack.count) slots") {
                if !stack.isEmpty {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(stack, id: \.self) { v in
                            Button { stack.removeAll { $0 == v } } label: {
                                HStack(spacing: 4) {
                                    Text(Format.kg(v)).monospacedDigit()
                                    Image(systemName: "xmark").font(.caption2.weight(.bold)).foregroundStyle(Theme.grey)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(PillButton())
                        }
                    }
                    .padding(.vertical, 4)
                }
                HStack {
                    TextField("Add a slot", text: $extra)
                        .keyboardType(.decimalPad)
                        .focused($typing)
                    Button("Add") { add() }
                        .buttonStyle(.borderless)
                        .disabled(Double(extra.replacingOccurrences(of: ",", with: ".")) == nil)
                }
                if !stack.isEmpty {
                    Button("Remove All", role: .destructive) { stack = [] }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Weight Stack")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard let first = stack.first, let last = stack.last else { return }
            from = Format.kg(first)
            to = Format.kg(last)
            if stack.count > 1 { step = Format.kg(stack[1] - first) }
        }
    }

    private func value(_ text: String) -> Double? { Double(text.replacingOccurrences(of: ",", with: ".")) }

    private var filled: [Double] {
        guard let a = value(from), let d = value(step), let b = value(to) else { return [] }
        return Exercise.slots(from: a, step: d, to: b)
    }

    private func add() {
        guard let v = value(extra), v >= 0 else { return }
        if !stack.contains(where: { abs($0 - v) < 0.001 }) { stack = (stack + [v]).sorted() }
        extra = ""
    }

    private func number(_ title: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(Theme.grey)
            TextField("–", text: text)
                .keyboardType(.decimalPad)
                .focused($typing)
                .font(.body.weight(.semibold))
                .monospacedDigit()
        }
    }
}

struct MusclePicker: View {
    @Binding var selected: [Muscle]

    var body: some View {
        List(Muscle.allCases, id: \.self) { m in
            Button {
                if let i = selected.firstIndex(of: m) { _ = selected.remove(at: i) } else { selected.append(m) }
            } label: {
                HStack {
                    Text(m.title).foregroundStyle(.white)
                    Spacer()
                    if selected.contains(m) { Image(systemName: "checkmark").foregroundStyle(Theme.blue) }
                }
            }
        }
        .navigationTitle("Other Muscles")
        .navigationBarTitleDisplayMode(.inline)
    }
}
