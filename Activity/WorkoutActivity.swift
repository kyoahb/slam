import ActivityKit
import SwiftUI

/// The workout in progress on the lock screen and in the Dynamic Island: the rest countdown while resting,
/// otherwise the time since it started. Shared by the app and the widget extension.
struct WorkoutActivity: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var exercise: String
        /// The set to do next: "Set 3 · 102 kg × 8".
        var next: String
        var restStart: Date?
        var restEnd: Date?
    }

    var start: Date
}

extension WorkoutActivity.ContentState {
    /// The rest still running, or nil once its end has passed (the activity is then stale).
    func rest(stale: Bool) -> ClosedRange<Date>? {
        guard !stale, let restStart, let restEnd, restStart < restEnd else { return nil }
        return restStart...restEnd
    }
}

enum ActivityStyle {
    static let blue = Color(red: 0x3D / 255, green: 0x8A / 255, blue: 0xF7 / 255)
    static let grey = Color(red: 0x84 / 255, green: 0x88 / 255, blue: 0x8C / 255)
}

/// Counts down a rest, or up from the workout's start.
struct ActivityClock: View {
    let start: Date
    let rest: ClosedRange<Date>?

    var body: some View {
        Group {
            if let rest {
                Text(timerInterval: rest, countsDown: true)
            } else {
                Text(start, style: .timer)
            }
        }
        .monospacedDigit()
        .foregroundStyle(rest == nil ? Color.white : ActivityStyle.blue)
    }
}

/// The lock screen banner.
struct WorkoutActivityView: View {
    let start: Date
    let state: WorkoutActivity.ContentState
    var stale = false

    var body: some View {
        let rest = state.rest(stale: stale)
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(state.exercise)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(state.next)
                        .font(.subheadline)
                        .foregroundStyle(ActivityStyle.grey)
                }
                .lineLimit(1)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(rest == nil ? "Workout" : "Rest")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ActivityStyle.grey)
                    ActivityClock(start: start, rest: rest)
                        .font(.system(size: 32, weight: .semibold))
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120, alignment: .trailing)
                }
            }
            if let rest {
                ProgressView(timerInterval: rest, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .tint(ActivityStyle.blue)
            }
        }
        .padding(16)
    }
}
