import SwiftUI
import SlamCore

/// Hevy's dark palette, near enough 1:1 for now.
enum Theme {
    static let bg = Color.black
    static let surface = Color(hex: 0x1C1C1D)
    static let line = Color(hex: 0x2C2C2D)
    static let control = Color(hex: 0x3A3A3C)
    static let blue = Color(hex: 0x3D8AF7)
    static let finish = Color(hex: 0x3B84E7)
    static let grey = Color(hex: 0x84888C)
    static let dim = Color(hex: 0x5B5E62)
    static let warm = Color(hex: 0xE4AC38)
    static let drop = Color(hex: 0x3D8AF7)
    static let green = Color(hex: 0x71BA41)
    static let doneRow = Color(hex: 0x1D2F17)
    static let rir = Color(hex: 0x3FC7D9)
    static let medal = Color(hex: 0xF0D044)
    static let red = Color(hex: 0xEB4D3D)
    static let left = Color(hex: 0x3D8AF7).opacity(0.10)
    static let right = Color(hex: 0xE4AC38).opacity(0.09)
    static let keypad = Color(hex: 0x141415)

    static func kindColor(_ kind: SetKind) -> Color {
        switch kind {
        case .warmup: warm
        case .drop: drop
        case .normal: .white
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

struct FillButton: ButtonStyle {
    var fill: Color = Theme.control
    var text: Color = .white
    var height: CGFloat = 44

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(text)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(RoundedRectangle(cornerRadius: 10).fill(fill))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct PillButton: ButtonStyle {
    var fill: Color = Theme.control
    var text: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(text)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(Capsule().fill(fill))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Exercise avatar: its photo, or initials on a grey circle.
struct Thumb: View {
    @Environment(AppModel.self) private var model
    let exercise: Exercise?
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            Circle().fill(Theme.control)
            if let file = exercise?.photo, let image = model.thumbnail(file) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Text(exercise?.initials ?? "?")
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(Theme.grey)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

struct StatColumn: View {
    let title: String
    let value: String
    var tint: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(Theme.grey)
            Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(tint).monospacedDigit()
        }
    }
}

struct Tag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.control))
    }
}

extension Date {
    var dayTitle: String { formatted(.dateTime.weekday(.wide).day().month(.abbreviated).year()) }
    var shortDay: String { formatted(.dateTime.day().month(.abbreviated)) }
    var time: String { formatted(date: .omitted, time: .shortened) }

    /// Today, Yesterday, Monday 6 Oct, or with the year when it is not this one.
    var relativeDay: String {
        let cal = Calendar.current
        if cal.isDateInToday(self) { return "Today" }
        if cal.isDateInYesterday(self) { return "Yesterday" }
        if cal.isDate(self, equalTo: Date(), toGranularity: .year) {
            return formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
        }
        return formatted(.dateTime.day().month(.abbreviated).year())
    }
}
