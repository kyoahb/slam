import SwiftUI
import SlamCore

struct SaveWorkoutView: View {
    @Environment(AppModel.self) private var model
    @Bindable var editor: WorkoutEditor
    @State private var routinePrompt: RoutinePrompt?
    @State private var confirmDiscard = false

    struct RoutinePrompt: Identifiable {
        let id = UUID()
        let routine: Routine
        let text: String
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    TextField("Workout title", text: $editor.workout.title)
                        .font(.title2.weight(.semibold))
                    if !editor.workout.title.isEmpty {
                        Button { editor.workout.title = "" } label: {
                            Image(systemName: "xmark").foregroundStyle(Theme.grey)
                        }
                    }
                }
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    HStack(spacing: 28) {
                        StatColumn(title: "Duration", value: Format.duration(editor.workout.duration), tint: Theme.blue)
                        StatColumn(title: "Volume", value: Format.volume(editor.volume))
                        StatColumn(title: "Sets", value: String(editor.doneCount))
                        Spacer()
                    }
                }
                Divider().overlay(Theme.line)
                PhotoStrip(photos: $editor.workout.photos)
                Divider().overlay(Theme.line)
                TextField("", text: $editor.workout.notes,
                          prompt: Text("How did your workout go? Leave some notes here...").foregroundColor(Theme.dim),
                          axis: .vertical)
                    .lineLimit(3...8)
                Divider().overlay(Theme.line)
                WorkoutFacts(workout: $editor.workout)
                Divider().overlay(Theme.line)
                Button("Discard Workout") { confirmDiscard = true }
                    .foregroundStyle(Theme.red)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
            .padding(16)
        }
        .background(Theme.bg)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Save Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.blue)
            }
        }
        .sheet(item: $routinePrompt) { p in
            UpdateRoutineSheet(name: p.routine.name, text: p.text) { update in
                routinePrompt = nil
                model.finishActive(updateRoutine: update)
            }
            .presentationDetents([.height(330)])
        }
        .confirmationDialog("Discard this workout?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard Workout", role: .destructive) { model.discardActive() }
        }
        .onChange(of: editor.workout) { editor.changed() }
    }

    private func save() {
        if let r = model.routine(editor.workout.routineId),
           let text = RoutineDiff.describe(editor.cleaned(), r, model.byId) {
            routinePrompt = RoutinePrompt(routine: r, text: text)
        } else {
            model.finishActive(updateRoutine: false)
        }
    }
}

/// When and where: shared by Save Workout and Edit Workout.
struct WorkoutFacts: View {
    @Environment(AppModel.self) private var model
    @Binding var workout: Workout
    var showsEnd = false
    @State private var addingGym = false
    @State private var gymName = ""

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("When").foregroundStyle(Theme.grey)
                Spacer()
                DatePicker("", selection: $workout.start).labelsHidden()
            }
            if showsEnd {
                HStack {
                    Text("Finished").foregroundStyle(Theme.grey)
                    Spacer()
                    DatePicker("", selection: Binding(get: { workout.end ?? workout.start },
                                                      set: { workout.end = max($0, workout.start) }),
                               in: workout.start...)
                        .labelsHidden()
                }
            }
            HStack {
                Text("Gym").foregroundStyle(Theme.grey)
                Spacer()
                Menu {
                    ForEach(model.gyms) { g in
                        Button {
                            workout.gymId = g.id
                        } label: {
                            if workout.gymId == g.id { Label(g.name, systemImage: "checkmark") } else { Text(g.name) }
                        }
                    }
                    Button("No Gym") { workout.gymId = nil }
                    Button("New Gym…", systemImage: "plus") {
                        gymName = ""
                        addingGym = true
                    }
                } label: {
                    Text(model.gym(workout.gymId)?.name ?? "Select")
                        .foregroundStyle(model.gym(workout.gymId) == nil ? Theme.grey : .white)
                        .lineLimit(1)
                }
            }
        }
        .alert("New Gym", isPresented: $addingGym) {
            TextField("Gym name", text: $gymName)
            Button("Add") {
                let n = gymName.trimmingCharacters(in: .whitespaces)
                if !n.isEmpty { workout.gymId = model.addGym(n).id }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct UpdateRoutineSheet: View {
    let name: String
    let text: String
    let done: (Bool) -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 34))
                .foregroundStyle(Theme.grey)
                .padding(.top, 24)
            Text("Update \"\(name)\"").font(.title3.weight(.semibold))
            Text(text).font(.subheadline).foregroundStyle(Theme.grey).multilineTextAlignment(.center)
            Spacer(minLength: 0)
            Button("Update Routine") { done(true) }
                .buttonStyle(FillButton(fill: Theme.blue))
            Button("Keep Original Routine") { done(false) }
                .buttonStyle(FillButton(fill: Theme.surface))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .interactiveDismissDisabled()
    }
}
