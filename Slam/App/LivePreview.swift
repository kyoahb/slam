import SwiftUI

/// Screenshot mode only: the Live Activity as the lock screen and the Dynamic Island show it.
struct LivePreview: View {
    let start: Date
    let state: WorkoutActivity.ContentState

    var body: some View {
        let rest = state.rest(stale: false)
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(hue: 0.62, saturation: 0.5, brightness: 0.35), .black],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            HStack {
                Image(systemName: rest == nil ? "dumbbell.fill" : "timer")
                    .foregroundStyle(ActivityStyle.blue)
                Spacer()
                ActivityClock(start: start, rest: rest)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 48)
            }
            .padding(.horizontal, 14)
            .frame(width: 250, height: 37)
            .background(.black, in: Capsule())
            .padding(.top, 11)
            .ignoresSafeArea()
            VStack(spacing: 4) {
                Text(Date.now, format: .dateTime.hour().minute())
                    .font(.system(size: 84, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.top, 70)
                Spacer()
                WorkoutActivityView(start: start, state: state)
                    .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 24))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 120)
            }
        }
    }
}
