import SwiftUI
import SlamCore

struct ActiveWorkoutView: View {
    @Environment(AppModel.self) private var model
    @Bindable var editor: WorkoutEditor
    @State private var showClock = false
    @State private var showSettings = false
    @State private var confirmDiscard = false
    @State private var askUnfinished = false
    @State private var nothingDone = false

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(editor.workout.exercises) { entry in
                ExerciseCard(editor: editor, entry: entry)
                Divider().overlay(Theme.line)
            }
            VStack(spacing: 10) {
                Button { editor.picking = true } label: {
                    Label("Add Exercise", systemImage: "plus")
                }
                .buttonStyle(FillButton(fill: Theme.blue))
                HStack(spacing: 10) {
                    Button("Settings") { showSettings = true }
                        .buttonStyle(FillButton(fill: Theme.surface))
                    Button("Discard Workout") { confirmDiscard = true }
                        .buttonStyle(FillButton(fill: Theme.surface, text: Theme.red))
                }
            }
            .padding(16)
            .padding(.bottom, 20)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView { list }
                .onChange(of: editor.focus) { _, focus in
                    if let focus { withAnimation { proxy.scrollTo(focus.set, anchor: .center) } }
                }
                .onAppear {
                    if let focus = editor.focus { proxy.scrollTo(focus.set, anchor: .center) }
                }
            }
            .background(Theme.bg)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if editor.focus != nil {
                    Keypad(editor: editor)
                } else if model.restEnd != nil {
                    RestBar()
                }
            }
            .navigationTitle("Log Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { model.showWorkout = false } label: {
                        Image(systemName: "chevron.down")
                    }
                    .accessibilityLabel("Minimise")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showClock = true } label: { clockLabel }
                        .accessibilityLabel("Clock")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Finish") { finish() }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.finish)
                }
            }
            .navigationDestination(isPresented: $editor.saving) { SaveWorkoutView(editor: editor) }
            .sheet(isPresented: $showClock) {
                ClockSheet().environment(model).presentationDetents([.medium])
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack { SettingsView(sheet: true) }.environment(model)
            }
            .confirmationDialog("Discard this workout?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard Workout", role: .destructive) { model.discardActive() }
            }
            .confirmationDialog("Some sets are not ticked", isPresented: $askUnfinished, titleVisibility: .visible) {
                Button("Complete Unfinished Sets") {
                    editor.completeUnfinished()
                    editor.saving = true
                }
                Button("Discard Unfinished Sets", role: .destructive) { editor.saving = true }
            }
            .alert("No sets ticked yet", isPresented: $nothingDone) {
                Button("OK", role: .cancel) {}
            }
            .editorSheets(editor)
        }
        .overlay(alignment: .top) {
            if let banner = editor.banner {
                SwipeAway(seconds: model.demo ? 600 : 4) {
                    if editor.banner?.id == banner.id { editor.banner = nil }
                } content: {
                    RecordBannerView(banner: banner)
                }
                .id(banner.id)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.45, bounce: 0.25), value: editor.banner?.id)
        .sensoryFeedback(.impact(weight: .medium), trigger: editor.doneTick)
        .sensoryFeedback(.success, trigger: editor.recordTick)
    }

    private var header: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            HStack(spacing: 28) {
                StatColumn(title: "Duration", value: Format.duration(editor.workout.duration), tint: Theme.blue)
                StatColumn(title: "Volume", value: Format.volume(editor.volume))
                StatColumn(title: "Sets", value: String(editor.doneCount))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Theme.bg)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
        }
    }

    @ViewBuilder
    private var clockLabel: some View {
        if let end = model.restEnd {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(Format.clock(Int(end.timeIntervalSince(ctx.date).rounded(.up))))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.blue)
            }
        } else {
            Image(systemName: "timer")
        }
    }

    private func finish() {
        editor.select(nil)
        if editor.doneCount == 0 && editor.unfinished == 0 {
            nothingDone = true
        } else if editor.unfinished > 0 {
            askUnfinished = true
        } else {
            editor.saving = true
        }
    }
}

/// Sheets every editor screen shares.
struct EditorSheets: ViewModifier {
    @Environment(AppModel.self) private var model
    @Bindable var editor: WorkoutEditor

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $editor.picking) {
                ExercisePicker { editor.add($0) }.environment(model)
            }
            .sheet(item: $editor.replacing) { ref in
                ExercisePicker(single: true, replacing: editor.entry(ref.id).flatMap { model.byId[$0.exerciseId] }) { list in
                    if let ex = list.first { editor.replace(ref.id, with: ex) }
                }
                .environment(model)
            }
            .sheet(isPresented: $editor.reordering) {
                ReorderSheet(editor: editor).environment(model)
            }
            .sheet(item: $editor.settingsFor) { ref in
                EntrySettingsSheet(editor: editor, entryId: ref.id)
                    .environment(model)
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $editor.historyFor) { link in
                NavigationStack {
                    ExerciseDetailView(id: link.id, page: 1)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Done") { editor.historyFor = nil } }
                        }
                        .navigationDestination(for: WorkoutLink.self) { WorkoutDetailView(id: $0.id, readOnly: true) }
                        .navigationDestination(for: ExerciseLink.self) { ExerciseDetailView(id: $0.id, page: 1) }
                }
                .environment(model)
            }
            .sheet(item: $editor.editingExercise) { link in
                if let ex = model.byId[link.id] {
                    NavigationStack {
                        ExerciseForm(exercise: ex, isNew: false)
                    }
                    .environment(model)
                }
            }
    }
}

extension ExerciseLink: Identifiable {}

extension View {
    func editorSheets(_ editor: WorkoutEditor) -> some View {
        modifier(EditorSheets(editor: editor))
    }
}

struct ReorderSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Bindable var editor: WorkoutEditor

    var body: some View {
        NavigationStack {
            List {
                ForEach(editor.workout.exercises) { entry in
                    HStack(spacing: 12) {
                        Thumb(exercise: model.byId[entry.exerciseId], size: 34)
                        Text(editor.exercise(entry).name).lineLimit(1)
                    }
                    .listRowBackground(Theme.bg)
                }
                .onMove { editor.move(from: $0, to: $1) }
            }
            .listStyle(.plain)
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Reorder Exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

struct EntrySettingsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Bindable var editor: WorkoutEditor
    let entryId: UUID

    var body: some View {
        NavigationStack {
            Form {
                if let ex = editor.exercise(entry: entryId) {
                    let list = ex.settings.filter { editor.mode != .routine || !$0.perWorkout }
                    ForEach(list) { c in
                        HStack {
                            Text(c.name)
                            TextField("–", text: Binding(get: { editor.setting(entryId, c.id) },
                                                         set: { editor.setSetting(entryId, c.id, $0) }))
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    Section {
                        NavigationLink(list.isEmpty ? "Add Seat, Pad or Incline Settings" : "Edit Exercise") {
                            ExerciseForm(exercise: ex, isNew: false)
                        }
                    }
                }
            }
            .navigationTitle(editor.exercise(entry: entryId)?.name ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
