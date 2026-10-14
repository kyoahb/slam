import SwiftUI
import SlamCore

struct WorkoutTab: View {
    @Environment(AppModel.self) private var model
    @State private var naming: Naming?
    @State private var name = ""
    @State private var pending: PendingStart?
    @State private var collapsed: Set<UUID> = []
    @State private var deleting: Routine?

    enum Naming: Identifiable {
        case newFolder, rename(Folder)
        var id: String {
            switch self {
            case .newFolder: "new"
            case .rename(let f): f.id.uuidString
            }
        }
    }

    struct PendingStart: Identifiable {
        let id = UUID()
        let routine: Routine?
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Quick Start").font(.headline)
                    Button { start(nil) } label: {
                        Label("Start Empty Workout", systemImage: "plus")
                    }
                    .buttonStyle(FillButton(fill: Theme.surface))

                    HStack {
                        Text("Routines").font(.headline)
                        Spacer()
                        Button {
                            name = ""
                            naming = .newFolder
                        } label: {
                            Image(systemName: "folder.badge.plus").font(.title3)
                        }
                        .accessibilityLabel("New Folder")
                    }
                    .padding(.top, 8)
                    Button { model.editRoutine(nil) } label: {
                        Label("New Routine", systemImage: "list.bullet.clipboard")
                    }
                    .buttonStyle(FillButton(fill: Theme.surface))

                    ForEach(model.folders) { folder in
                        folderSection(folder.name, id: folder.id, folder: folder,
                                      routines: model.routines.filter { $0.folderId == folder.id })
                    }
                    let loose = model.routines.filter { r in r.folderId == nil || !model.folders.contains { $0.id == r.folderId } }
                    if !loose.isEmpty || model.folders.isEmpty {
                        folderSection("My Routines", id: nil, folder: nil, routines: loose)
                    }
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("Workout")
            .navigationBarTitleDisplayMode(.inline)
            .alert(namingTitle,
                   isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
                TextField("Folder name", text: $name)
                Button("Save") {
                    let n = name.trimmingCharacters(in: .whitespaces)
                    if !n.isEmpty, let naming {
                        switch naming {
                        case .newFolder: model.addFolder(n)
                        case .rename(let f): model.rename(folder: f, to: n)
                        }
                    }
                    naming = nil
                }
                Button("Cancel", role: .cancel) { naming = nil }
            }
            .confirmationDialog("You have a workout in progress", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                                titleVisibility: .visible, presenting: pending) { p in
                Button("Resume Workout") { model.showWorkout = true }
                Button("Discard and Start New", role: .destructive) {
                    model.discardActive()
                    begin(p.routine)
                }
            }
            .confirmationDialog("Delete this routine?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible, presenting: deleting) { r in
                Button("Delete Routine", role: .destructive) { model.delete(routine: r) }
            }
        }
        .workoutBar()
    }

    private var namingTitle: String {
        if case .rename = naming { return "Rename Folder" }
        return "New Folder"
    }

    @ViewBuilder
    private func folderSection(_ title: String, id: UUID?, folder: Folder?, routines: [Routine]) -> some View {
        let key = id ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        let isCollapsed = collapsed.contains(key)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    if isCollapsed { _ = collapsed.remove(key) } else { collapsed.insert(key) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.footnote.weight(.semibold))
                        Text("\(title) (\(routines.count))").font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(Theme.grey)
                }
                .buttonStyle(.plain)
                Spacer()
                if let folder {
                    Menu {
                        Button("New Routine Here", systemImage: "plus") { model.editRoutine(nil, folder: folder.id) }
                        Button("Rename Folder", systemImage: "pencil") {
                            name = folder.name
                            naming = .rename(folder)
                        }
                        Button("Delete Folder", systemImage: "trash", role: .destructive) { model.delete(folder: folder) }
                    } label: {
                        Image(systemName: "ellipsis").foregroundStyle(Theme.grey).frame(width: 32, height: 28)
                    }
                }
            }
            if !isCollapsed {
                ForEach(routines) { r in routineCard(r) }
            }
        }
        .padding(.top, 6)
    }

    private func routineCard(_ r: Routine) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(r.name).font(.headline)
                Spacer()
                Menu {
                    Button("Edit Routine", systemImage: "pencil") { model.editRoutine(r) }
                    Button("Duplicate Routine", systemImage: "plus.square.on.square") { model.duplicate(r) }
                    Menu("Move to Folder") {
                        Button("No Folder") { model.move(r, to: nil) }
                        ForEach(model.folders) { f in
                            Button(f.name) { model.move(r, to: f.id) }
                        }
                    }
                    Button("Delete Routine", systemImage: "trash", role: .destructive) { deleting = r }
                } label: {
                    Image(systemName: "ellipsis").foregroundStyle(Theme.grey).frame(width: 32, height: 24)
                }
            }
            Text(r.exercises.compactMap { model.byId[$0.exerciseId]?.name }.joined(separator: ", "))
                .font(.subheadline)
                .foregroundStyle(Theme.grey)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Start Routine") { start(r) }
                .buttonStyle(FillButton(fill: Theme.blue, height: 40))
                .padding(.top, 4)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
    }

    private func start(_ r: Routine?) {
        if model.editor != nil {
            pending = PendingStart(routine: r)
        } else {
            begin(r)
        }
    }

    private func begin(_ r: Routine?) {
        if let r { model.start(r) } else { model.startEmpty() }
    }
}

struct RoutineEditorView: View {
    @Environment(AppModel.self) private var model
    @Bindable var editor: WorkoutEditor

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        TextField("Routine title", text: $editor.workout.title)
                            .font(.title3.weight(.semibold))
                            .padding(16)
                        Divider().overlay(Theme.line)
                        ForEach(editor.workout.exercises) { entry in
                            ExerciseCard(editor: editor, entry: entry)
                            Divider().overlay(Theme.line)
                        }
                        Button { editor.picking = true } label: {
                            Label("Add exercise", systemImage: "plus")
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
            .safeAreaInset(edge: .bottom) {
                if editor.focus != nil { Keypad(editor: editor) }
            }
            .navigationTitle(editor.isNew ? "Create Routine" : "Edit Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { model.routineEditor = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { model.saveRoutine(from: editor) }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.blue)
                }
            }
            .editorSheets(editor)
        }
        .interactiveDismissDisabled()
    }
}
