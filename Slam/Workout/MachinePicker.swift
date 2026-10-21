import SwiftUI
import SlamCore

/// Which machine an exercise is done on: none, one already set up, or a new one holding what the exercise has now.
struct MachinePicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Binding var exercise: Exercise
    @Binding var newMachine: Machine?
    @Binding var picked: Bool
    @State private var naming = false
    @State private var name = ""

    var body: some View {
        List {
            Section {
                row("None", on: exercise.machineId == nil) { pick(nil) }
                Button("New Machine", systemImage: "plus") {
                    name = exercise.name
                    naming = true
                }
                .foregroundStyle(Theme.blue)
            } footer: {
                Text("Exercises on one machine share its weights and settings. Each keeps its own history and records.")
            }
            if !machines.isEmpty {
                Section("Machines") {
                    ForEach(machines) { m in
                        let count = model.onMachine(m.id).count
                        row(m.name, brand: m.brand, detail: count == 1 ? "1 exercise" : "\(count) exercises",
                            on: exercise.machineId == m.id) { pick(m) }
                            .swipeActions {
                                if count == 0 && m.id != newMachine?.id {
                                    Button("Delete", role: .destructive) { model.delete(machine: m) }
                                }
                            }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("Machine")
        .navigationBarTitleDisplayMode(.inline)
        .alert("New Machine", isPresented: $naming) {
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) {}
            Button("Add") { create() }
        } message: {
            Text("It starts with this exercise's weights and settings.")
        }
    }

    private var machines: [Machine] {
        var list = model.machines
        if let m = newMachine, !list.contains(where: { $0.id == m.id }) { list.append(m) }
        return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func row(_ title: String, brand: String = "", detail: String? = nil, on: Bool,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).foregroundStyle(.white).lineLimit(2)
                    if let detail {
                        HStack(spacing: 6) {
                            Text(detail).font(.subheadline).foregroundStyle(Theme.grey)
                            if !brand.isEmpty { Tag(text: brand) }
                        }
                    }
                }
                Spacer(minLength: 0)
                if on { Image(systemName: "checkmark").foregroundStyle(Theme.blue) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func pick(_ m: Machine?) {
        if let m, m.id == exercise.machineId {
            // Already on it: keep what was changed in the form.
        } else if let m {
            exercise = exercise.moved(to: m)
        } else {
            exercise.machineId = nil
        }
        picked = true
        dismiss()
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let m = Machine(name: trimmed, from: exercise)
        newMachine = m
        exercise.machineId = m.id
        picked = true
        dismiss()
    }
}
