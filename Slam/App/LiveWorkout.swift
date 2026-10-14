import ActivityKit
import SlamCore

extension AppModel {
    /// Puts the workout in progress on the lock screen and in the Dynamic Island, keeps it current,
    /// and takes it away once the workout is over.
    func refreshLiveActivity() {
        guard !demo else { return }
        let running = Activity<WorkoutActivity>.activities
        guard let editor else {
            for a in running { Task { await a.end(nil, dismissalPolicy: .immediate) } }
            return
        }
        let start = editor.workout.start
        let content = ActivityContent(state: liveState(editor), staleDate: restEnd)
        for a in running where a.attributes.start != start { Task { await a.end(nil, dismissalPolicy: .immediate) } }
        if let a = running.first(where: { $0.attributes.start == start }) {
            Task { await a.update(content) }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            _ = try? Activity.request(attributes: WorkoutActivity(start: start), content: content)
        }
    }

    /// The first set not yet ticked, and the rest if one is running.
    func liveState(_ editor: WorkoutEditor) -> WorkoutActivity.ContentState {
        var state = WorkoutActivity.ContentState(exercise: editor.workout.title, next: "All sets done")
        for e in editor.workout.exercises {
            guard let i = e.sets.firstIndex(where: { !$0.done }), let ex = byId[e.exerciseId] else { continue }
            let s = e.sets[i].filled(from: editor.placeholders(e)[i])
            let label = switch s.kind {
            case .warmup: "Warm-up"
            case .drop: "Drop set"
            case .normal: "Set " + Previous.labels(e.sets)[i]
            }
            let values = SetText.describe(s, ex)
            state.exercise = ex.name
            state.next = s.isEmpty || values.isEmpty ? label : label + " · " + values
            break
        }
        if let end = restEnd {
            state.restStart = end.addingTimeInterval(-Double(max(1, restLength)))
            state.restEnd = end
        }
        return state
    }
}
