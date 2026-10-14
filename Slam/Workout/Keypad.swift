import SwiftUI
import SlamCore

/// Digits, or what the exercise needs to make up its weight; the bar on top shows the parts and their total.
/// RIR sits on top for reps.
struct Keypad: View {
    @Bindable var editor: WorkoutEditor

    static let keyColor = Color(hex: 0x2C2C2E)
    static let height: CGFloat = 4 * 46 + 3 * 6

    var body: some View {
        let f = editor.focus
        let ex = f?.field == .kg ? f.flatMap { editor.exercise(entry: $0.entry) } : nil
        VStack(spacing: 6) {
            if let f, f.field == .reps || f.field == .repsR, editor.set(f)?.kind != .warmup {
                rirBar(f)
            } else if let f, let ex {
                weightBar(f, ex)
            }
            HStack(spacing: 6) {
                if let f, let ex {
                    weight(f, ex)
                } else {
                    digits
                }
                VStack(spacing: 6) {
                    key(Image(systemName: "keyboard.chevron.compact.down")) { editor.select(nil) }
                        .frame(height: 46)
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
            .frame(height: Self.height)
        }
        .padding(.horizontal, 6)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .background(Theme.keypad.ignoresSafeArea(edges: .bottom))
    }

    // MARK: Keys

    @ViewBuilder
    private func weight(_ f: Cell, _ ex: Exercise) -> some View {
        switch ex.rig {
        case .barbell, .plateLoaded:
            plates(f, label: ex.sides > 1 ? "EACH SIDE ×2" : "ONE SIDE")
        case .stack where editor.pinPlates:
            plates(f, label: "PIN")
        case .stack where !ex.stack.isEmpty:
            slots(f, ex.stack)
        case .dumbbell:
            dumbbell(f)
        default:
            digits
        }
    }

    private var digits: some View {
        digitRows { _ in EmptyView() }
    }

    /// 1 to 9, then . 0 ⌫; `extra` adds a fourth key to each row.
    private func digitRows<E: View>(@ViewBuilder extra: @escaping (Int) -> E) -> some View {
        VStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { r in
                HStack(spacing: 6) {
                    if r < 3 {
                        ForEach(1...3, id: \.self) { c in
                            let d = r * 3 + c
                            key(Text(String(d))) { editor.key(.digit(d)) }
                        }
                    } else {
                        key(Text(".")) { editor.key(.dot) }
                            .disabled(!(editor.focus?.field.allowsDot ?? false))
                        key(Text("0")) { editor.key(.digit(0)) }
                        key(Image(systemName: "delete.left")) { editor.key(.back) }
                    }
                    extra(r)
                }
            }
        }
    }

    /// Digits for the dumbbell, its clip-ons down the side: each one on or off. Last time's are outlined.
    private func dumbbell(_ f: Cell) -> some View {
        let on = editor.load(f)?.plates ?? []
        let own = editor.set(f)?.kg != nil
        return digitRows { r in
            let p = Plates.micro[r]
            let picked = on.contains { abs($0 - p) < 0.01 }
            Button { editor.toggleClip(p) } label: {
                Text("+" + Format.kg(p))
                    .font(.system(size: 17, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(picked && own ? .black : Theme.plate)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 8).fill(picked && own ? Theme.plate : Self.keyColor))
                    .overlay {
                        if picked && !own { RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.plate, lineWidth: 2) }
                    }
            }
            .buttonStyle(.plain)
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

    /// The stack's slots: the picked one filled, last time's outlined. Tapping the picked one clears it.
    private func slots(_ f: Cell, _ stack: [Double]) -> some View {
        let own = editor.set(f)?.kg != nil ? editor.load(f)?.base : nil
        let last = own == nil ? editor.load(f)?.base : nil
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
            .frame(maxWidth: .infinity)
            .onAppear { scroll(proxy, stack, to: own ?? last) }
            .onChange(of: f) { scroll(proxy, stack, to: editor.load(f)?.base) }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, _ stack: [Double], to value: Double?) {
        guard let value, let slot = stack.min(by: { abs($0 - value) < abs($1 - value) }) else { return }
        proxy.scrollTo(slot, anchor: .center)
    }

    /// The plates as they sit on the sleeve (tap one to take it off), then a key per plate to put one on.
    private func plates(_ f: Cell, label: String) -> some View {
        let list = editor.load(f)?.plates ?? []
        let own = editor.set(f)?.kg != nil
        let sizes = Plates.standard
        return VStack(spacing: 6) {
            HStack(spacing: 0) {
                UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 3)
                    .fill(Theme.dim)
                    .frame(width: 26, height: 10)
                RoundedRectangle(cornerRadius: 2).fill(Theme.grey).frame(width: 8, height: 26)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 3) {
                        ForEach(Array(list.enumerated()), id: \.offset) { i, p in
                            Button { editor.removePlate(at: i) } label: { plate(p) }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Take off \(Format.kg(p)) kg")
                        }
                    }
                    .padding(.leading, 3)
                    .frame(height: 82)
                    .opacity(own ? 1 : 0.35)
                }
                .background {
                    UnevenRoundedRectangle(bottomTrailingRadius: 3, topTrailingRadius: 3)
                        .fill(Theme.control)
                        .frame(height: 10)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topTrailing) {
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .kerning(0.5)
                    .foregroundStyle(Theme.plate)
                    .padding(.top, 7)
                    .padding(.trailing, 10)
            }
            .background(RoundedRectangle(cornerRadius: 8).strokeBorder(Self.keyColor, lineWidth: 1.5))
            .frame(height: 98)
            ForEach([Array(sizes.prefix(4)), Array(sizes.dropFirst(4))], id: \.self) { line in
                HStack(spacing: 6) {
                    ForEach(line, id: \.self) { p in
                        key(Text("+" + Format.kg(p)).font(.system(size: 19, weight: .medium)).monospacedDigit()) {
                            editor.addPlate(p)
                        }
                    }
                    if line.count < 4 {
                        key(Text("Clear").font(.system(size: 17, weight: .semibold))) { editor.clearPlates() }
                            .disabled(list.isEmpty)
                    }
                }
            }
        }
    }

    private func plate(_ kg: Double) -> some View {
        let heights: [Double: CGFloat] = [25: 80, 20: 74, 15: 64, 10: 54, 5: 44, 2.5: 36, 1.25: 30]
        return Text(Format.kg(kg))
            .font(.system(size: kg < 2 ? 9 : kg < 5 ? 10 : 11, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(Color(hex: 0x1B1230))
            .frame(width: 26, height: heights[kg] ?? 30)
            .background(RoundedRectangle(cornerRadius: 4).fill(Theme.plate))
    }

    // MARK: The weight's parts

    /// One box with the total, or the parts that make it up and their sum. Stack and Pin are tabs,
    /// the add-on switches on and off, a bar or machine's own weight is fixed.
    @ViewBuilder
    private func weightBar(_ f: Cell, _ ex: Exercise) -> some View {
        let s = editor.set(f)
        let own = s?.kg != nil
        let l = editor.load(f) ?? ex.emptyLoad
        let empty = editor.load(f) == nil
        let sign = { (v: String) in v == "–" ? v : ex.type.kgSign + v }
        let total = own || !empty || ex.rig == .barbell || ex.rig == .plateLoaded ? Format.kg(l.total) : "–"
        let plateText = Format.kg(l.plates.reduce(0, +))
        switch ex.rig {
        case .stack:
            let pin = ex.pin || !l.plates.isEmpty
            let typed = ex.stack.isEmpty
            if ex.addOn == nil && !pin {
                single(stackTitle(ex), Theme.blue, sign(typed ? editor.partText(f) ?? "–" : total), dim: !own)
            } else {
                parts(sign(total), dim: !own) {
                    Button { editor.pinPlates = false } label: {
                        Chip(label: "STACK", ink: Theme.blue, value: (typed ? editor.partText(f) : nil) ?? Format.kg(l.base),
                             look: editor.pinPlates ? .key : .active(Theme.blue, Color(hex: 0x16263F)),
                             tail: typed && !editor.pinPlates ? .caret : nil)
                    }
                    .buttonStyle(.plain)
                    if let a = ex.addOn {
                        plus("+")
                        Button { editor.toggleAddOn() } label: {
                            Chip(label: "ADD-ON", ink: Theme.grey, value: Format.kg(a), badge: .toggle(l.addOn > 0),
                                 off: l.addOn <= 0)
                        }
                        .buttonStyle(.plain)
                    }
                    if pin {
                        plus("+")
                        Button { editor.pinPlates = true } label: {
                            Chip(label: "PIN", ink: Theme.plate, value: plateText,
                                 look: editor.pinPlates ? .active(Theme.plate, Color(hex: 0x2A2238)) : .key)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        case .barbell, .plateLoaded:
            if l.base <= 0 && ex.rig == .plateLoaded {
                single("Plates", Theme.plate, total, sub: ex.sides > 1 ? "each side ×2" : "one side", dim: !own)
            } else {
                parts(total, dim: !own) {
                    Chip(label: ex.rig == .barbell ? "BAR" : "MACHINE", ink: Theme.grey, value: Format.kg(l.base),
                         look: .locked, badge: .lock)
                    plus(ex.sides > 1 ? "+ 2×" : "+")
                    Chip(label: ex.sides > 1 ? "EACH SIDE" : "ONE SIDE", ink: Theme.plate, value: plateText,
                         look: .active(Theme.plate, Color(hex: 0x2A2238)))
                }
            }
        case .dumbbell:
            if l.plates.isEmpty {
                single("Dumbbell", Theme.blue, editor.partText(f) ?? "–", dim: !own)
            } else {
                parts(total, dim: !own) {
                    Chip(label: "DUMBBELL", ink: Theme.blue, value: editor.partText(f) ?? "–",
                         look: .active(Theme.blue, Color(hex: 0x16263F)), tail: .caret)
                    plus("+")
                    Button { editor.clearPlates() } label: {
                        Chip(label: "CLIP-ONS", ink: Theme.plate, value: plateText, tail: .clear)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Take off clip-ons")
                }
            }
        case .plain:
            single(plainTitle(ex), Theme.blue, sign(editor.text(f) ?? editor.placeholderText(f) ?? "–"),
                   dim: editor.text(f) == nil)
        }
    }

    private func stackTitle(_ ex: Exercise) -> String {
        switch ex.type {
        case .assistedBodyweight: "Assistance"
        case .bodyweightReps: "Added weight"
        default: "Stack"
        }
    }

    private func plainTitle(_ ex: Exercise) -> String {
        switch ex.type {
        case .assistedBodyweight: "Assistance"
        case .bodyweightReps: "Added weight"
        default: ex.equipment == .none || ex.equipment == .other ? "Weight" : ex.equipment.title
        }
    }

    /// A box with what the weight is and its total.
    private func single(_ title: String, _ ink: Color, _ total: String, sub: String? = nil, dim: Bool) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(ink)
            if let sub { Text(sub).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.grey) }
            Spacer(minLength: 0)
            kg(total, dim: dim)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 8).strokeBorder(Self.keyColor, lineWidth: 1.5))
    }

    /// Parts joined by +, then = the total.
    private func parts<C: View>(_ total: String, dim: Bool, @ViewBuilder _ chips: () -> C) -> some View {
        HStack(spacing: 5) {
            chips()
            Spacer(minLength: 0)
            plus("=")
            kg(total, dim: dim).padding(.trailing, 4)
        }
        .frame(height: 40)
    }

    private func plus(_ text: String) -> some View {
        Text(text).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.dim).fixedSize()
    }

    private func kg(_ value: String, dim: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(dim ? Theme.grey : .white)
            Text("kg").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.grey)
        }
        .monospacedDigit()
        .lineLimit(1)
        .fixedSize()
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
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(RoundedRectangle(cornerRadius: 8).fill(current == v ? Theme.rir : Self.keyColor))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// One part of a weight: a small label over its value.
private struct Chip: View {
    enum Look { case key, active(Color, Color), locked }
    enum Badge { case lock, toggle(Bool) }
    enum Tail { case caret, clear }

    let label: String
    let ink: Color
    let value: String
    var look: Look = .key
    var badge: Badge?
    var tail: Tail?
    var off = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(label).font(.system(size: 10, weight: .bold)).kerning(0.5).foregroundStyle(ink)
                switch badge {
                case .lock:
                    Image(systemName: "lock.fill").font(.system(size: 8)).foregroundStyle(Theme.grey)
                case .toggle(let on):
                    Capsule()
                        .fill(on ? Theme.green : Color(hex: 0x48484A))
                        .frame(width: 20, height: 12)
                        .overlay(alignment: on ? .trailing : .leading) {
                            Circle().fill(on ? .white : Color(hex: 0xA0A3A7)).frame(width: 8, height: 8).padding(2)
                        }
                case nil:
                    EmptyView()
                }
            }
            HStack(spacing: tail == .caret ? 2 : 6) {
                Text(value)
                    .font(.system(size: 17, weight: .semibold))
                    .monospacedDigit()
                    .strikethrough(off)
                    .foregroundStyle(.white)
                switch tail {
                case .caret: Rectangle().fill(Theme.blue).frame(width: 2, height: 17)
                case .clear: Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.grey)
                case nil: EmptyView()
                }
            }
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background { background }
        .contentShape(Rectangle())
    }

    @ViewBuilder private var background: some View {
        let shape = RoundedRectangle(cornerRadius: 8)
        switch look {
        case .key:
            shape.fill(Keypad.keyColor)
        case .active(let edge, let fill):
            shape.fill(fill).overlay(shape.strokeBorder(edge, lineWidth: 1.5))
        case .locked:
            shape.strokeBorder(Theme.control, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
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
