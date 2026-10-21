import SwiftUI
import SlamCore

struct WorkoutDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let id: UUID
    /// Opened over the workout in progress: looked at, not changed.
    var readOnly = false
    @State private var editing: WorkoutEditor?
    @State private var confirmDelete = false
    @State private var naming = false
    @State private var routineName = ""
    @State private var viewing: Photo?

    var body: some View {
        if let w = model.workout(id) {
            content(w)
        } else {
            ContentUnavailableView("Workout deleted", systemImage: "trash")
        }
    }

    private func content(_ w: Workout) -> some View {
        let records = model.records[w.id]?.count ?? 0
        let gym: String = model.gym(w.gymId).map { " · \($0.name)" } ?? ""
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(w.title.isEmpty ? "Workout" : w.title).font(.title2.weight(.bold))
                    Text("\(w.start.dayTitle), \(w.start.time)\(gym)")
                        .font(.footnote)
                        .foregroundStyle(Theme.grey)
                }
                HStack(spacing: 24) {
                    StatColumn(title: "Time", value: Format.duration(w.duration))
                    StatColumn(title: "Volume", value: Format.volume(Stats.volume(w, model.byId)))
                    StatColumn(title: "Sets", value: String(Stats.sets(w)))
                    if records > 0 { StatColumn(title: "Records", value: String(records), tint: Theme.medal) }
                    Spacer(minLength: 0)
                }
                if !w.notes.isEmpty {
                    Text(w.notes).font(.subheadline)
                }
                if !w.photos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(w.photos) { p in
                                Button { viewing = p } label: {
                                    StoredImage(file: p.file)
                                        .frame(width: 140, height: 140)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                Divider().overlay(Theme.line)
                ForEach(w.exercises) { e in
                    exercise(w, e)
                    Divider().overlay(Theme.line)
                }
            }
            .padding(16)
        }
        .background(Theme.bg)
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: ShareText.workout(w, model)) { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("Share workout")
            }
            if !readOnly {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Edit Workout", systemImage: "pencil") {
                            editing = WorkoutEditor(workout: w, mode: .past, app: model)
                        }
                        Button("Save as Routine", systemImage: "list.bullet.clipboard") {
                            routineName = w.title
                            naming = true
                        }
                        Button("Delete Workout", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
        }
        .fullScreenCover(item: $editing) { ed in
            EditWorkoutView(editor: ed).environment(model)
        }
        .fullScreenCover(item: $viewing) { p in
            PhotoViewer(photo: p).environment(model)
        }
        .confirmationDialog("Delete this workout?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Workout", role: .destructive) {
                dismiss()
                model.delete(w)
            }
        }
        .alert("Save as Routine", isPresented: $naming) {
            TextField("Routine name", text: $routineName)
            Button("Save") {
                let name = routineName.trimmingCharacters(in: .whitespaces)
                model.save(routine: Routine.from(w, name: name.isEmpty ? "New Routine" : name, exercises: model.byId))
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func exercise(_ w: Workout, _ e: WorkoutExercise) -> some View {
        let ex = model.byId[e.exerciseId] ?? Exercise(id: e.exerciseId, name: "Deleted exercise")
        let records = model.entryRecords(w, e)
        let settings = model.settingsText(e)
        return VStack(alignment: .leading, spacing: 8) {
            NavigationLink(value: ExerciseLink(id: ex.id)) {
                HStack(spacing: 10) {
                    Thumb(exercise: ex, size: 40)
                    Text(ex.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.blue)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    if let t = model.trend(w, e) { TrendBadge(trend: t) }
                }
            }
            .buttonStyle(.plain)
            if !e.note.isEmpty { Text(e.note).font(.subheadline) }
            if !settings.isEmpty { Text(settings).font(.subheadline).foregroundStyle(Theme.grey) }
            if let link = e.watch { WatchLine(link: link) }
            SetGrid(entry: e, exercise: ex, records: records)
            RecordLine(records: records)
        }
    }
}

/// A finished workout opened for changes: same cards and keypad as the live one.
struct EditWorkoutView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Bindable var editor: WorkoutEditor

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 14) {
                            TextField("Workout title", text: $editor.workout.title)
                                .font(.title3.weight(.semibold))
                            WorkoutFacts(workout: $editor.workout, showsEnd: true)
                            PhotoStrip(photos: $editor.workout.photos)
                            TextField("", text: $editor.workout.notes,
                                      prompt: Text("How did your workout go? Leave some notes here...").foregroundColor(Theme.dim),
                                      axis: .vertical)
                                .lineLimit(2...8)
                        }
                        .padding(16)
                        Divider().overlay(Theme.line)
                        ForEach(editor.workout.exercises) { entry in
                            ExerciseCard(editor: editor, entry: entry)
                            Divider().overlay(Theme.line)
                        }
                        Button { editor.picking = true } label: {
                            Label("Add Exercise", systemImage: "plus")
                        }
                        .buttonStyle(FillButton(fill: Theme.blue))
                        .padding(16)
                    }
                }
                .onChange(of: editor.focus) { _, focus in
                    if let focus { withAnimation { proxy.scrollTo(focus.set, anchor: .center) } }
                }
            }
            .background(Theme.bg)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if editor.focus != nil { Keypad(editor: editor) }
            }
            .navigationTitle("Edit Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        editor.select(nil)
                        model.insert(editor.cleaned())
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.blue)
                }
            }
            .editorSheets(editor)
        }
        .interactiveDismissDisabled()
    }
}
