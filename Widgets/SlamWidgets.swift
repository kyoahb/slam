import ActivityKit
import SwiftUI
import WidgetKit

@main
struct SlamWidgets: WidgetBundle {
    var body: some Widget {
        WorkoutLiveActivity()
    }
}

struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivity.self) { context in
            WorkoutActivityView(start: context.attributes.start, state: context.state, stale: context.isStale)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let start = context.attributes.start
            let rest = context.state.rest(stale: context.isStale)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(rest == nil ? "Workout" : "Rest", systemImage: rest == nil ? "dumbbell.fill" : "timer")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ActivityStyle.blue)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ActivityClock(start: start, rest: rest)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 110, alignment: .trailing)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.exercise).font(.headline).foregroundStyle(.white)
                        Text(context.state.next).font(.subheadline).foregroundStyle(ActivityStyle.grey)
                    }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: rest == nil ? "dumbbell.fill" : "timer")
                    .foregroundStyle(ActivityStyle.blue)
            } compactTrailing: {
                ActivityClock(start: start, rest: rest)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 48)
            } minimal: {
                ActivityClock(start: start, rest: rest)
                    .font(.caption2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 34)
            }
            .keylineTint(ActivityStyle.blue)
        }
    }
}
