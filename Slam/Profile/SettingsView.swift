import SwiftUI
import SlamCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var sheet = false
    @State private var naming: Gym?
    @State private var addingGym = false
    @State private var gymName = ""
    @State private var export: ExportFile?
    @State private var confirmDelete = false
    @State private var deleting = false

    struct ExportFile: Identifiable {
        let url: URL
        var id: URL { url }
    }

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Rest Timer") {
                RestStepper(title: "Rest", seconds: $model.settings.restSeconds)
                RestStepper(title: "After warm-up", seconds: $model.settings.warmupRestSeconds)
            }
            Section("Gyms") {
                ForEach(model.gyms) { g in
                    Button {
                        model.settings.gymId = g.id
                    } label: {
                        HStack {
                            Text(g.name).foregroundStyle(.white)
                            Spacer()
                            if model.settings.gymId == g.id { Image(systemName: "checkmark").foregroundStyle(Theme.blue) }
                        }
                    }
                    .contextMenu {
                        Button("Rename", systemImage: "pencil") {
                            gymName = g.name
                            naming = g
                        }
                    }
                    .swipeActions {
                        if !used(g) {
                            Button("Delete", role: .destructive) { model.delete(gym: g) }
                        }
                        Button("Rename") {
                            gymName = g.name
                            naming = g
                        }
                        .tint(Theme.control)
                    }
                }
                Button("Add Gym", systemImage: "plus") {
                    gymName = ""
                    addingGym = true
                }
            }
            SyncSection()
            Section {
                Button("Export Data", systemImage: "square.and.arrow.up") {
                    if let url = model.exportFile() { export = ExportFile(url: url) }
                }
            }
            Section {
                Button(role: .destructive) { confirmDelete = true } label: {
                    HStack {
                        Label("Delete All Data", systemImage: "trash")
                        if deleting {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(deleting)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if sheet {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .onChange(of: model.settings) { model.saveSettings() }
        .alert("New Gym", isPresented: $addingGym) {
            TextField("Gym name", text: $gymName)
            Button("Add") {
                let n = gymName.trimmingCharacters(in: .whitespaces)
                if !n.isEmpty { model.addGym(n) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename Gym", isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField("Gym name", text: $gymName)
            Button("Save") {
                let n = gymName.trimmingCharacters(in: .whitespaces)
                if let g = naming, !n.isEmpty { model.rename(gym: g, to: n) }
                naming = nil
            }
            Button("Cancel", role: .cancel) { naming = nil }
        }
        .confirmationDialog("Delete all data?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete All Data", role: .destructive) {
                deleting = true
                Task {
                    await model.deleteAllData()
                    deleting = false
                }
            }
        } message: {
            Text(model.syncConfig == nil
                 ? "Every workout, routine, exercise, gym and photo on this phone is deleted."
                 : "Every workout, routine, exercise, gym and photo is deleted, on this phone and on the server.")
        }
        .sheet(item: $export) { f in
            ShareSheet(items: [f.url]).presentationDetents([.medium, .large])
        }
    }

    private func used(_ g: Gym) -> Bool { model.workouts.contains { $0.gymId == g.id } }
}

/// The Slam server on your PC: when this phone last synced with it.
struct SyncSection: View {
    @Environment(AppModel.self) private var model
    @State private var confirmOff = false

    var body: some View {
        Section {
            if let config = model.syncConfig {
                HStack {
                    Text(config.url.host() ?? "Server")
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    status
                }
                if let error = model.syncStatus.error {
                    Text(error).font(.footnote).foregroundStyle(Theme.red)
                }
                Button("Sync Now", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await model.syncNow() }
                }
                .disabled(model.syncStatus.running)
                Button("Turn Off Sync", role: .destructive) { confirmOff = true }
            } else {
                Text("Scan the setup code on your PC with the Camera.")
                    .foregroundStyle(Theme.grey)
            }
        } header: {
            Text("Sync")
        }
        .confirmationDialog("Turn off sync?", isPresented: $confirmOff, titleVisibility: .visible) {
            Button("Turn Off", role: .destructive) { model.turnOffSync() }
        } message: {
            Text("Your data stays on this phone and on the server.")
        }
    }

    @ViewBuilder private var status: some View {
        if model.syncStatus.running {
            ProgressView()
        } else if let last = model.syncStatus.last {
            Text(last.formatted(.relative(presentation: .named)))
                .foregroundStyle(model.syncStatus.error == nil ? Theme.grey : Theme.red)
        } else {
            Text("Never").foregroundStyle(Theme.grey)
        }
    }
}

struct RestStepper: View {
    let title: String
    @Binding var seconds: Int

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Button { seconds = max(0, seconds - 15) } label: {
                Image(systemName: "minus").frame(width: 34, height: 30)
            }
            .buttonStyle(.borderless)
            Text(seconds == 0 ? "Off" : Format.clock(seconds))
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .frame(width: 56)
            Button { seconds = min(900, seconds + 15) } label: {
                Image(systemName: "plus").frame(width: 34, height: 30)
            }
            .buttonStyle(.borderless)
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
