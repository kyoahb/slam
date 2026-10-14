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

/// Create or edit an exercise. Hevy's fields plus L/R, weight setup, brand and machine settings.
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
                if exercise.type.hasKg {
                    Picker("Weight Setup", selection: $exercise.load) {
                        ForEach(LoadKind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
            }
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
                    if !e.type.hasKg { e.load = .plain }
                    onSave(e)
                    dismiss()
                }
                .disabled(exercise.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
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
