import SwiftUI
import WatchKit
import SlamCore

private enum Tint {
    static let blue = Color(red: 0x3D / 255, green: 0x8A / 255, blue: 0xF7 / 255)
    static let green = Color(red: 0x71 / 255, green: 0xBA / 255, blue: 0x41 / 255)
    static let grey = Color(red: 0x84 / 255, green: 0x88 / 255, blue: 0x8C / 255)
    static let control = Color(red: 0x3A / 255, green: 0x3A / 255, blue: 0x3C / 255)
}

/// The rest, the set to do with its setup, then the sets after it.
struct WristView: View {
    @Environment(WristModel.self) private var model

    var body: some View {
        if let state = model.state {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    clock(state)
                    if let now = state.sets.first {
                        current(now)
                    } else {
                        Text("All sets done").foregroundStyle(Tint.grey)
                    }
                    upcoming(state.sets)
                }
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "dumbbell.fill").font(.title2).foregroundStyle(Tint.blue)
                Text("Start a workout on your iPhone").multilineTextAlignment(.center).foregroundStyle(Tint.grey)
            }
        }
    }

    /// The rest counting down while there is one, else how long the workout has run.
    private func clock(_ state: WristState) -> some View {
        TimelineView(.explicit(state.restEnd.map { [$0] } ?? [])) { context in
            if let end = state.restEnd, end > context.date {
                let start = min(end.addingTimeInterval(-Double(max(1, state.restLength))), context.date)
                VStack(spacing: 6) {
                    Text(timerInterval: start...end, countsDown: true)
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity)
                    ProgressView(timerInterval: start...end, countsDown: true) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .tint(Tint.blue)
                    HStack(spacing: 6) {
                        Button("−15") { model.adjust(-15) }
                        Button("+15") { model.adjust(15) }
                        Button("Skip") { model.skip() }
                    }
                    .font(.footnote.weight(.semibold))
                }
            } else {
                HStack {
                    Text(state.title).font(.footnote).foregroundStyle(Tint.grey).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(state.start, style: .timer).font(.footnote).monospacedDigit()
                }
            }
        }
    }

    private func current(_ line: WristState.Line) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(line.exercise).font(.headline).foregroundStyle(Tint.blue).lineLimit(2)
            if !line.settings.isEmpty {
                Text(line.settings).font(.footnote).foregroundStyle(Tint.grey)
            }
            Text(line.label).font(.footnote).foregroundStyle(Tint.grey).padding(.top, 4)
            Text(line.values.isEmpty ? "–" : line.values).font(.title3.weight(.semibold))
            if let setup = line.setup {
                Text(setup).font(.footnote)
            }
            HoldDone { model.done(line) }.id(line.set).padding(.top, 6)
        }
    }

    @ViewBuilder
    private func upcoming(_ sets: [WristState.Line]) -> some View {
        if sets.count > 1 {
            VStack(alignment: .leading, spacing: 4) {
                Text("Next").font(.footnote.weight(.semibold)).foregroundStyle(Tint.grey)
                ForEach(Array(sets.enumerated().dropFirst()), id: \.element.set) { i, line in
                    if line.entry != sets[i - 1].entry {
                        Text(line.exercise).font(.footnote.weight(.semibold)).foregroundStyle(Tint.blue)
                            .lineLimit(2).padding(.top, 4)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(line.label).foregroundStyle(Tint.grey)
                        Spacer(minLength: 4)
                        Text(line.values.isEmpty ? "–" : line.values)
                    }
                    .font(.footnote)
                    if let setup = line.setup {
                        Text(setup).font(.caption2).foregroundStyle(Tint.grey)
                    }
                }
            }
        }
    }
}

/// Held for half a second, like the tick on the phone, so a brush of the sleeve does nothing.
struct HoldDone: View {
    let action: () -> Void
    @State private var fill: CGFloat = 0

    var body: some View {
        Capsule()
            .fill(Tint.control)
            .overlay(alignment: .leading) {
                GeometryReader { g in
                    Rectangle().fill(Tint.green).frame(width: g.size.width * fill)
                }
            }
            .clipShape(Capsule())
            .overlay {
                Label("Hold for Done", systemImage: "checkmark").font(.footnote.weight(.semibold))
            }
            .frame(height: 40)
            .contentShape(Capsule())
            .onLongPressGesture(minimumDuration: 0.5) {
                var instant = Transaction()
                instant.disablesAnimations = true
                withTransaction(instant) { fill = 0 }
                action()
            } onPressingChanged: { pressing in
                withAnimation(pressing ? .linear(duration: 0.5) : .easeOut(duration: 0.15)) { fill = pressing ? 1 : 0 }
            }
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Done")
            .accessibilityAction { action() }
    }
}
