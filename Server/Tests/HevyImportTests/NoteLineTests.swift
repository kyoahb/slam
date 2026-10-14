import XCTest
@testable import HevyImport

/// Note lines read with invented rules: "zp" is the pin word, "c" a counter, "rri" a slip of "rir".
final class NoteLineTests: XCTestCase {
    private let grammar = Grammar(Rules(aliases: ["rri": "rir"], pinWords: ["zp"], counters: ["c"]))

    private func read(_ s: String, addOns: Set<Double> = [2.5]) -> NoteLine {
        guard let line = grammar.read(s, addOns: addOns) else {
            XCTFail("no line for \(s)")
            return NoteLine(raw: s, norm: s, dropped: IndexSet())
        }
        return line
    }

    private func loadout(_ s: String) -> Loadout? {
        read(s).frags.lazy.compactMap { f -> Loadout? in
            if case .load(let l) = f.value { return l }
            return nil
        }.first
    }

    private func kinds(_ s: String) -> [String] { read(s).frags.map(\.kind) }

    func testStackWithAddOnAndPinPlates() throws {
        let l = try XCTUnwrap(loadout("100 + 2.5 (10 5)zp"))
        XCTAssertEqual(l.shape, "L_PIN")
        XCTAssertEqual(l.base, 100)
        XCTAssertEqual(l.addOn, 2.5)
        XCTAssertEqual(l.plates, [10, 5])
        XCTAssertTrue(l.pinned)
        XCTAssertEqual(l.total, 117.5)
    }

    func testPlatesASide() throws {
        let l = try XCTUnwrap(loadout("20 5 a side"))
        XCTAssertEqual(l.shape, "L_PERSIDE")
        XCTAssertEqual(l.plates, [20, 5])
        XCTAssertEqual(l.sides, 2)
        XCTAssertEqual(l.total, 50)
        XCTAssertEqual(loadout("wu 12.5 a side")?.prefix, "wu")
        XCTAssertEqual(loadout("15 a side; 15 bar")?.total, 45)
    }

    func testDumbbellWithClipOns() throws {
        let l = try XCTUnwrap(loadout("30 + 2(0.5)"))
        XCTAssertEqual(l.shape, "L_BASE_COUNT")
        XCTAssertEqual(l.base, 30)
        XCTAssertEqual(l.plates, [0.5, 0.5])
        XCTAssertEqual(l.total, 31)
    }

    func testCommaDecimalsAndBareDecimals() {
        XCTAssertEqual(loadout("1,5 a side")?.plates, [1.5])
        XCTAssertEqual(loadout(".5 a side")?.plates, [0.5])
    }

    func testLeftAndRightReps() {
        for s in ["11L9R", "9R11L", "11l 9r"] {
            guard case .sides(let l, let r)? = read(s).frags.first?.value else { return XCTFail(s) }
            XCTAssertEqual([l, r], ["11", "9"], s)
        }
    }

    func testEffort() {
        let line = read("3: 2-3rir")
        XCTAssertEqual(line.setIndex, 3)
        guard case .rir(let a, let b)? = line.frags.first?.value else { return XCTFail("no rir") }
        XCTAssertEqual(Frag.Value.rirValue(a, b), 3)
        XCTAssertEqual(kinds("0"), ["RIR"])
        XCTAssertEqual(kinds("2 rri"), ["RIR"])
        XCTAssertEqual(kinds("failed"), ["FAIL"])
    }

    func testWholeRir() {
        XCTAssertEqual(Frag.Value.rirValue(-1, nil), 0)
        XCTAssertEqual(Frag.Value.rirValue(0.5, nil), 1)
        XCTAssertEqual(Frag.Value.rirValue(2.5, nil), 3)
        XCTAssertEqual(Frag.Value.rirValue(0, 1), 1)
    }

    func testSettings() {
        guard case .setting(let n, let v)? = read("seat at 9").frags.first?.value else { return XCTFail("seat") }
        XCTAssertEqual(n, "seat")
        XCTAssertEqual(v, "9")
        guard case .shows(let n2, let shown)? = read("at 3 shows 7").frags.first?.value else { return XCTFail("shows") }
        XCTAssertNil(n2)
        XCTAssertEqual(shown, "7")
        guard case .shows(let n3, _)? = read("pad shows 6").frags.first?.value else { return XCTFail("pad") }
        XCTAssertEqual(n3, "pad")
    }

    func testDroppedParts() {
        XCTAssertEqual(kinds("3c"), ["EXTRA"])
        XCTAssertEqual(kinds("6 down"), ["ADJUST"])
        XCTAssertEqual(kinds("upstairs"), ["LOC"])
    }

    func testPlanLine() {
        XCTAssertTrue(read("next time try 105").plan)
        XCTAssertFalse(read("105 + 2.5").plan)
    }

    func testLeftover() {
        let line = read("100 + 2.5 (10 5)zp felt strong")
        XCTAssertEqual(line.leftover(Set(line.frags.indices)), "felt strong")
        XCTAssertEqual(line.leftover([]), "100 + 2.5 (10 5)zp felt strong")
        let plain = read("felt strong")
        XCTAssertEqual(plain.leftover([]), "felt strong")
        let indexed = read("4: 3rir")
        XCTAssertEqual(indexed.leftover(Set(indexed.frags.indices)), "")
        XCTAssertEqual(read("1:").leftover([]), "")
        XCTAssertEqual(read("1: rir").leftover([]), "")
    }

    func testNameTidy() {
        XCTAssertEqual(Names.tidy("cable  fly ( high)"), "Cable Fly (High)")
        XCTAssertEqual(Names.tidy("row on the bench"), "Row on the Bench")
    }
}
