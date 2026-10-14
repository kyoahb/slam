import Foundation

public enum Format {
    /// 121, 118.5, 1.25 — no trailing zeros, no unit.
    public static func kg(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        var s = String(format: "%.2f", rounded)
        while s.hasSuffix("0") { s.removeLast() }
        return s
    }

    /// 12,345
    public static func grouped(_ value: Double) -> String {
        let n = Int(value.rounded())
        let digits = String(abs(n))
        var out = ""
        for (i, ch) in digits.enumerated() {
            if i > 0, (digits.count - i) % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return n < 0 ? "-" + out : out
    }

    public static func volume(_ kg: Double) -> String { grouped(kg) + " kg" }

    /// 1h 2min, 45min, 12min 3s, 40s
    public static func duration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let h = total / 3600, m = total % 3600 / 60, s = total % 60
        if h > 0 { return m > 0 ? "\(h)h \(m)min" : "\(h)h" }
        if m > 0 { return s > 0 && m < 10 ? "\(m)min \(s)s" : "\(m)min" }
        return "\(s)s"
    }

    /// 2:05, 1:02:05
    public static func clock(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let h = total / 3600, m = total % 3600 / 60, s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    /// 2.4 (km)
    public static func km(_ meters: Double) -> String { kg(meters / 1000) }

    /// Seconds typed as digits filling from the right: "130" → 1:30, "10000" → 1:00:00.
    public static func secondsFromDigits(_ digits: String) -> Int? {
        let d = digits.filter(\.isNumber)
        guard !d.isEmpty, let n = Int(d.suffix(6)) else { return nil }
        let s = n % 100, m = n / 100 % 100, h = n / 10000
        return h * 3600 + m * 60 + s
    }

    public static func digits(fromSeconds seconds: Int) -> String {
        let h = seconds / 3600, m = seconds % 3600 / 60, s = seconds % 60
        let n = h * 10000 + m * 100 + s
        return n == 0 ? "" : String(n)
    }
}
