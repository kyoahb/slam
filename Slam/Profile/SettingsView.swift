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

    struct ExportFile: Identifiable {
        let url: URL
        var id: URL { url }
    }

    static let plateSizes: [Double] = [0.5, 1.25, 2.5, 5, 10, 15, 20, 25]

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
            Section("Plates") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(Self.plateSizes, id: \.self) { p in
                        let on = model.settings.plates.contains(p)
                        Button(Format.kg(p)) { toggle(p) }
                            .buttonStyle(PillButton(fill: on ? Theme.blue : Theme.control))
                    }
                }
                .padding(.vertical, 4)
            }
            Section {
                Button("Export Data", systemImage: "square.and.arrow.up") {
                    if let url = model.exportFile() { export = ExportFile(url: url) }
                }
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
        .sheet(item: $export) { f in
            ShareSheet(items: [f.url]).presentationDetents([.medium, .large])
        }
    }

    private func used(_ g: Gym) -> Bool { model.workouts.contains { $0.gymId == g.id } }

    private func toggle(_ p: Double) {
        if let i = model.settings.plates.firstIndex(of: p) {
            model.settings.plates.remove(at: i)
        } else {
            model.settings.plates.append(p)
            model.settings.plates.sort()
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
