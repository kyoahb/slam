import SwiftUI
import SlamCore

/// Digits, or the machine's stack slots for its weight. RIR sits on top for reps, the add-on switch for weight.
struct Keypad: View {
    @Bindable var editor: WorkoutEditor

    static let keyColor = Color(hex: 0x2C2C2E)

    var body: some View {
        let f = editor.focus
        let ex = f.flatMap { editor.exercise(entry: $0.entry) }
        VStack(spacing: 6) {
            if let f, f.field == .reps || f.field == .repsR, editor.set(f)?.kind != .warmup {
                rirBar(f)
            } else if let f, f.field == .kg, let amount = ex?.addOn {
                addOnBar(f, amount)
            }
            HStack(spacing: 6) {
                if let f, f.field == .kg, let stack = ex?.stack, !stack.isEmpty {
                    slots(f, stack)
                } else {
                    digits
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

    private var digits: some View {
        VStack(spacing: 6) {
            row([1, 2, 3])
            row([4, 5, 6])
            row([7, 8, 9])
            HStack(spacing: 6) {
                key(Text(".")) { editor.key(.dot) }
                    .disabled(!(editor.focus?.field.allowsDot ?? false))
                key(Text("0")) { editor.key(.digit(0)) }
                key(Image(systemName: "delete.left")) { editor.key(.back) }
            }
        }
    }

    private func row(_ list: [Int]) -> some View {
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
                .background(RoundedRectangle(cornerRadius: 8).fill(Self.keyColor))
        }
        .buttonStyle(.plain)
    }

    /// The stack's slots: the picked one filled, last time's outlined.
    private func slots(_ f: Cell, _ stack: [Double]) -> some View {
        let own = editor.set(f)?.base
        let last = own == nil ? editor.placeholder(f)?.base : nil
        func same(_ a: Double?, _ b: Double) -> Bool { a.map { abs($0 - b) < 0.01 } ?? false }
        return ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(stack, id: \.self) { v in
                        Button { editor.pickSlot(v) } label: {
                            Text(Format.kg(v))
                                .font(.system(size: 20, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 46)
                                .background(RoundedRectangle(cornerRadius: 8).fill(same(own, v) ? Theme.blue : Self.keyColor))
                                .overlay {
                                    if same(last, v) { RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.blue, lineWidth: 2) }
                                }
                        }
                        .buttonStyle(.plain)
                        .id(v)
                    }
                }
            }
            .onAppear { scroll(proxy, stack, to: own ?? last) }
            .onChange(of: f) { scroll(proxy, stack, to: editor.set(f)?.base ?? editor.placeholder(f)?.base) }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, _ stack: [Double], to value: Double?) {
        guard let value, let slot = stack.min(by: { abs($0 - value) < abs($1 - value) }) else { return }
        proxy.scrollTo(slot, anchor: .center)
    }

    private func addOnBar(_ f: Cell, _ amount: Double) -> some View {
        let on = editor.addOn(f) != nil
        return HStack(spacing: 6) {
            Text("Add-on")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.blue)
                .frame(width: 56)
            segment("+0", selected: !on) { if on { editor.toggleAddOn() } }
            segment("+" + Format.kg(amount) + " kg", selected: on) { if !on { editor.toggleAddOn() } }
        }
    }

    private func segment(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Theme.blue : Self.keyColor))
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
                        .background(RoundedRectangle(cornerRadius: 8).fill(current == v ? Theme.rir : Self.keyColor))
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
