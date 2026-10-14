import Foundation

public enum Plates {
    public static let standard: [Double] = [1.25, 2.5, 5, 10, 15, 20, 25]

    static func units(_ kg: Double) -> Int { Int((kg * 4).rounded()) }

    /// Fewest plates adding up to `kg`, largest first. Nil when no mix of `available` makes it exactly.
    public static func compose(_ kg: Double, from available: [Double]) -> [Double]? {
        let target = units(kg)
        if target == 0 { return [] }
        guard target > 0 else { return nil }
        let (best, sizes) = table(target, available)
        guard best[target] != .max else { return nil }
        return unwind(target, best, sizes)
    }

    /// The heaviest amount up to `kg` that `available` can make, as fewest plates.
    public static func closest(_ kg: Double, from available: [Double]) -> [Double] {
        let target = units(kg)
        guard target > 0 else { return [] }
        let (best, sizes) = table(target, available)
        guard let reach = (0...target).last(where: { best[$0] != .max }) else { return [] }
        return unwind(reach, best, sizes)
    }

    /// The same total in fewer plates, using nothing heavier than `maxPlate`. Nil when it is already tidy.
    public static func tidy(_ plates: [Double], available: [Double], maxPlate: Double? = nil) -> [Double]? {
        let limit = max(maxPlate ?? .infinity, plates.max() ?? 0)
        let allowed = available.filter { $0 <= limit + 0.001 }
        guard plates.count > 1, let better = compose(plates.reduce(0, +), from: allowed),
              better.count < plates.count else { return nil }
        return better
    }

    private static func table(_ target: Int, _ available: [Double]) -> ([Int], [Int]) {
        let sizes = Array(Set(available.map(units).filter { $0 > 0 })).sorted(by: >)
        var best = [Int](repeating: .max, count: target + 1)
        best[0] = 0
        if target > 0 {
            for amount in 1...target {
                for p in sizes where p <= amount && best[amount - p] != .max {
                    best[amount] = min(best[amount], best[amount - p] + 1)
                }
            }
        }
        return (best, sizes)
    }

    private static func unwind(_ target: Int, _ best: [Int], _ sizes: [Int]) -> [Double] {
        var out: [Double] = []
        var amount = target
        while amount > 0, let p = sizes.first(where: { $0 <= amount && best[amount - $0] == best[amount] - 1 }) {
            out.append(Double(p) / 4)
            amount -= p
        }
        return out
    }
}

public extension Load {
    var plateTotal: Double { plates.reduce(0, +) }

    func total(_ kind: LoadKind) -> Double {
        base + addOn + (kind == .plateLoaded ? 2 : 1) * plateTotal
    }

    /// Plate added (a pair when plate loaded), heaviest plates kept first.
    func adding(_ plate: Double) -> Load {
        var l = self
        l.plates.append(plate)
        l.plates.sort(by: >)
        return l
    }

    func removingPlate(at index: Int) -> Load {
        var l = self
        if l.plates.indices.contains(index) { l.plates.remove(at: index) }
        return l
    }

    /// Keeps the stack and add-on and builds the rest of `kg` from plates.
    /// Nil when the plates on hand cannot make the difference exactly.
    func retargeted(to kg: Double, kind: LoadKind, available: [Double], maxPlate: Double? = nil) -> Load? {
        var l = self
        let rest = kg - base - addOn
        if rest < -0.001 {
            // Lighter than the stack alone: the stack moved down.
            l.plates = []
            l.base = max(0, kg - addOn)
            if kg - addOn < 0 { l.addOn = 0; l.base = kg }
            return l
        }
        let perSide = kind == .plateLoaded ? rest / 2 : rest
        let limit = max(maxPlate ?? .infinity, plates.max() ?? 0)
        let allowed = available.filter { $0 <= limit + 0.001 }
        guard let made = Plates.compose(perSide, from: allowed) ?? Plates.compose(perSide, from: available) else { return nil }
        l.plates = made
        return l
    }
}
