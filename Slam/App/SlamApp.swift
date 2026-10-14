import SwiftUI
import SlamCore

@main
struct SlamApp: App {
    @State private var model = AppModel.launch()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(Theme.blue)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tab) {
            Tab("History", systemImage: "clock.arrow.circlepath", value: AppTab.history) { HistoryTab() }
            Tab("Workout", systemImage: "dumbbell", value: AppTab.workout) { WorkoutTab() }
            Tab("Profile", systemImage: "person", value: AppTab.profile) { ProfileTab() }
        }
        .fullScreenCover(isPresented: $model.showWorkout) {
            if let editor = model.editor {
                ActiveWorkoutView(editor: editor).environment(model)
            }
        }
        .sheet(item: $model.routineEditor) { editor in
            RoutineEditorView(editor: editor).environment(model)
        }
        .task(id: model.restEnd) {
            guard let end = model.restEnd else { return }
            let wait = end.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled, model.restEnd == end else { return }
            model.restFinished()
        }
        .sensoryFeedback(.success, trigger: model.restDoneTick)
    }
}

/// The workout in progress, minimised above the tab bar.
struct MiniWorkoutBar: View {
    @Environment(AppModel.self) private var model
    @State private var confirmDiscard = false

    var body: some View {
        if let editor = model.editor, !model.showWorkout {
            HStack(spacing: 12) {
                Button { model.showWorkout = true } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(editor.workout.title.isEmpty ? "Workout" : editor.workout.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            TimelineView(.periodic(from: .now, by: 1)) { _ in
                                Text(Format.duration(editor.workout.duration))
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(Theme.blue)
                                    .monospacedDigit()
                            }
                        }
                        Spacer(minLength: 0)
                        if let end = model.restEnd {
                            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                                Text(Format.clock(Int(end.timeIntervalSince(ctx.date).rounded(.up))))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.blue)
                                    .monospacedDigit()
                            }
                        }
                        Text("Resume").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.blue)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button { confirmDiscard = true } label: {
                    Image(systemName: "trash").foregroundStyle(Theme.red).frame(width: 32, height: 32)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
            .confirmationDialog("Discard this workout?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard Workout", role: .destructive) { model.discardActive() }
            }
        }
    }
}

extension View {
    func workoutBar() -> some View {
        safeAreaInset(edge: .bottom) { MiniWorkoutBar() }
    }
}
