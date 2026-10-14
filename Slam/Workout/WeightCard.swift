import SwiftUI
import SlamCore

/// Opens under a set when its KG is tapped: copy the set above, bump, or build the weight from its parts.
struct WeightCard: View {
    @Environment(AppModel.self) private var model
    @Bindable var editor: WorkoutEditor
    let cell: Cell
    let exercise: Exercise

    private var kgCell: Cell { Cell(entry: cell.entry, set: cell.set, field: .kg) }

    private var hasSetAbove: Bool {
        guard let e = editor.entry(cell.entry), let i = e.sets.firstIndex(where: { $0.id == cell.set }) else { return false }
        return i > 0
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Button { editor.sameAsAbove(kgCell) } label: {
                    Image(systemName: "equal")
                        .font(.system(size: 17, weight: .bold))
                        .frame(width: 44, height: 44)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.control))
                }
                .buttonStyle(.plain)
                .disabled(!hasSetAbove)
                .opacity(hasSetAbove ? 1 : 0.35)
                .accessibilityLabel("Same as set above")

                if exercise.load == .plain {
                    ForEach([-2.5, -1.25, 1.25, 2.5, 5], id: \.self) { d in
                        Button { editor.bump(kgCell, by: d) } label: {
                            Text((d > 0 ? "+" : "−") + Format.kg(abs(d)))
                                .font(.system(size: 15, weight: .semibold))
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.control))
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    parts
                }
            }
            if exercise.load != .plain { plateRow }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
        .padding(.horizontal, 16)
    }

    private var parts: some View {
        let load = editor.load(kgCell) ?? Load()
        let grey = editor.loadIsPlaceholder(kgCell)
        let pin = exercise.load == .pinMachine
        return HStack(spacing: 6) {
            part(pin ? "Stack" : "Bar", Format.kg(load.base), field: .stack, grey: grey)
            if pin { part("Add-on", Format.kg(load.addOn), field: .addOn, grey: grey) }
            VStack(alignment: .leading, spacing: 2) {
                Text(pin ? "Pin" : "Per side").font(.caption2).foregroundStyle(Theme.grey)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        if load.plates.isEmpty {
                            Text("–").font(.body.weight(.semibold)).foregroundStyle(Theme.dim)
                        }
                        ForEach(Array(load.plates.enumerated()), id: \.offset) { i, p in
                            Button { editor.removePlate(kgCell, at: i) } label: {
                                Text(Format.kg(p))
                                    .font(.system(size: 14, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(grey ? Theme.grey : .white)
                                    .padding(.horizontal, 7)
                                    .frame(height: 24)
                                    .background(Capsule().fill(Theme.control))
                            }
                            .buttonStyle(.plain)
                        }
                        if let tidy = editor.tidySuggestion(kgCell) {
                            Button { editor.tidy(kgCell) } label: {
                                Text("→ " + tidy.map { Format.kg($0) }.joined(separator: " "))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .frame(height: 24)
                                    .background(Capsule().fill(Theme.blue))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Fewer plates")
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.bg))
        }
    }

    private func part(_ title: String, _ value: String, field: Field, grey: Bool) -> some View {
        let focused = editor.focus?.field == field
        let typed = focused ? editor.text(Cell(entry: cell.entry, set: cell.set, field: field)) : nil
        return Button { editor.editPart(kgCell, field) } label: {
            VStack(spacing: 1) {
                Text(title).font(.caption2).foregroundStyle(Theme.grey)
                Text(typed ?? value)
                    .font(.system(size: 16, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(grey && !focused ? Theme.grey : .white)
            }
            .frame(minWidth: 54, minHeight: 44)
            .padding(.horizontal, 2)
            .background(RoundedRectangle(cornerRadius: 10).fill(focused ? Theme.control : Theme.bg))
        }
        .buttonStyle(.plain)
    }

    private var plateRow: some View {
        let biggest = editor.maxPlate(exercise.id)
        return HStack(spacing: 5) {
            ForEach(model.settings.plates.sorted(), id: \.self) { p in
                let awkward = biggest.map { p > $0 } ?? false
                Button { editor.addPlate(kgCell, p) } label: {
                    Text("+" + Format.kg(p))
                        .font(.system(size: 14, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(awkward ? Theme.grey : .white)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.control))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct Keypad: View {
    @Bindable var editor: WorkoutEditor

    var body: some View {
        VStack(spacing: 6) {
            if let f = editor.focus, f.field == .reps || f.field == .repsR, editor.set(f)?.kind != .warmup {
                rirBar(f)
            }
            HStack(spacing: 6) {
                VStack(spacing: 6) {
                    digits([1, 2, 3])
                    digits([4, 5, 6])
                    digits([7, 8, 9])
                    HStack(spacing: 6) {
                        key(Text(".")) { editor.key(.dot) }
                            .disabled(!(editor.focus?.field.allowsDot ?? false))
                        key(Text("0")) { editor.key(.digit(0)) }
                        key(Image(systemName: "delete.left")) { editor.key(.back) }
                    }
                }
                VStack(spacing: 6) {
                    key(Image(systemName: "keyboard.chevron.compact.down")) { editor.select(nil) }
                    Button { editor.next() } label: {
                        Text("Next")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.blue))
                    }
                    .buttonStyle(.plain)
                }
                .frame(width: 80)
            }
            .frame(height: 4 * 46 + 3 * 6)
        }
        .padding(.horizontal, 6)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .background(Theme.keypad.ignoresSafeArea(edges: .bottom))
    }

    private func digits(_ list: [Int]) -> some View {
        HStack(spacing: 6) {
            ForEach(list, id: \.self) { d in
                key(Text(String(d))) { editor.key(.digit(d)) }
            }
        }
    }

    private func key<L: View>(_ label: L, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x2C2C2E)))
        }
        .buttonStyle(.plain)
    }

    private func rirBar(_ f: Cell) -> some View {
        let current = editor.rir(f)
        return HStack(spacing: 6) {
            Text("RIR")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.rir)
                .frame(width: 34)
            ForEach(0...5, id: \.self) { v in
                Button { editor.setRIR(current == v ? nil : v) } label: {
                    Text(v == 5 ? "5+" : String(v))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(current == v ? .black : .white)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(RoundedRectangle(cornerRadius: 8).fill(current == v ? Theme.rir : Color(hex: 0x2C2C2E)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct RestBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let end = model.restEnd {
            TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
                let left = max(0, end.timeIntervalSince(ctx.date))
                let fraction = model.restLength > 0 ? min(1, left / Double(model.restLength)) : 0
                VStack(spacing: 0) {
                    GeometryReader { g in
                        Rectangle().fill(Theme.blue).frame(width: g.size.width * fraction)
                    }
                    .frame(height: 3)
                    HStack(spacing: 10) {
                        Button("-15") { model.adjustRest(-15) }.buttonStyle(PillButton())
                        Spacer()
                        Text(Format.clock(Int(left.rounded(.up))))
                            .font(.title2.weight(.semibold))
                            .monospacedDigit()
                        Spacer()
                        Button("+15") { model.adjustRest(15) }.buttonStyle(PillButton())
                        Button("Skip") { model.skipRest() }.buttonStyle(PillButton(fill: Theme.blue))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .background(Theme.surface.ignoresSafeArea(edges: .bottom))
            }
        }
    }
}

struct ClockSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var mode = 0
    @State private var length = 120

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Picker("", selection: $mode) {
                    Text("Timer").tag(0)
                    Text("Stopwatch").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
                    if mode == 0 { timer(ctx.date) } else { stopwatch(ctx.date) }
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            .navigationTitle("Clock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear { length = model.restEnd != nil ? model.restLength : model.settings.restSeconds }
        }
    }

    private func ring(_ value: String, fraction: Double) -> some View {
        ZStack {
            Circle().stroke(Theme.control, lineWidth: 8)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Theme.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(value).font(.system(size: 40, weight: .semibold)).monospacedDigit()
        }
        .frame(width: 170, height: 170)
    }

    @ViewBuilder
    private func timer(_ now: Date) -> some View {
        let resting = model.restEnd != nil
        let total = Double(max(1, resting ? model.restLength : length))
        let left = model.restEnd.map { max(0, $0.timeIntervalSince(now)) } ?? Double(length)
        VStack(spacing: 16) {
            ring(Format.clock(Int(left.rounded(.up))), fraction: resting ? left / total : 1)
            HStack(spacing: 14) {
                Button("-15s") {
                    if resting { model.adjustRest(-15) } else { length = max(15, length - 15) }
                }
                .buttonStyle(PillButton(text: Theme.blue))
                Button("+15s") {
                    if resting { model.adjustRest(15) } else { length += 15 }
                }
                .buttonStyle(PillButton(text: Theme.blue))
            }
            Button(resting ? "Skip" : "Start") {
                if resting { model.skipRest() } else { model.startRest(length) }
            }
            .buttonStyle(FillButton(fill: Theme.blue))
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private func stopwatch(_ now: Date) -> some View {
        let running = model.stopwatchStart != nil
        let elapsed = model.stopwatchBanked + (model.stopwatchStart.map { now.timeIntervalSince($0) } ?? 0)
        VStack(spacing: 16) {
            ring(Format.clock(Int(elapsed)), fraction: 1)
            HStack(spacing: 10) {
                Button("Reset") {
                    model.stopwatchStart = nil
                    model.stopwatchBanked = 0
                }
                .buttonStyle(FillButton(fill: Theme.surface))
                Button(running ? "Stop" : "Start") {
                    if let start = model.stopwatchStart {
                        model.stopwatchBanked += Date().timeIntervalSince(start)
                        model.stopwatchStart = nil
                    } else {
                        model.stopwatchStart = Date()
                    }
                }
                .buttonStyle(FillButton(fill: Theme.blue))
            }
            .padding(.horizontal, 16)
        }
    }
}
