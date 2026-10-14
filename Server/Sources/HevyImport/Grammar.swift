import Foundation

/// The patterns a note line is read with: plain gym shorthand, plus the person's own words from `Rules`.
final class Grammar {
    static let num = #"\d+(?:\.\d+)?"#
    static let number = Rx(num)

    let rules: Rules
    let aliases: [(Rx, String)]

    // Loadouts, tried in this order at the start of a line.
    let maxLine, perSide, barLine, pin, pinLoose, db, count, sum, plus, spaced, single, lead: Rx
    let countTerm, countLead, countParen, digitParen, pinWord: Rx

    // Everything else in a line.
    let setIndex, bareRirLine, bareRir, bareNotLoad, leadStop, leadLoad: Rx
    let sides2, sides2b, rir, rirR, side1, fail, named, unnamed, adjust, stacks, location, locationDigit: Rx
    let counters: Rx?
    let shows: [Rx]
    let keep: [Rx]
    let onLeg, inline, perSideAdd, plan: Rx

    init(_ rules: Rules) {
        self.rules = rules
        aliases = rules.aliases.sorted { $0.key.count > $1.key.count }.map { phrase, canonical in
            (Rx("(?<![a-z])" + NSRegularExpression.escapedPattern(for: phrase.lowercased()) + "(?![a-z])"), canonical)
        }

        let N = Grammar.num
        let pw = Grammar.alt(["pin"] + rules.pinWords)
        let pwt = Grammar.alt(["pin"] + rules.pinWords + rules.pinTypos)
        let side = #"(?:a|each|per)?\s*side"#
        let ct = #"\d{1,2}\s?(?:\(\s*N(?:\s*\+\s*N)*\s*\)|x\s?N)"#.replacingOccurrences(of: "N", with: N)

        func rx(_ p: String) -> Rx {
            Rx(p.replacingOccurrences(of: "{N}", with: N).replacingOccurrences(of: "{CT}", with: ct)
                .replacingOccurrences(of: "{PW}", with: pw).replacingOccurrences(of: "{PWT}", with: pwt)
                .replacingOccurrences(of: "{SIDE}", with: side))
        }

        maxLine = rx(#"(?:^|(?<=\s))max\s*(?:\(\s*(?<s>{N})\s*\))?(?<rest>(?:\s*\+\s*{N}\s*(?:kg)?)*)"#)
        perSide = rx(#"^(?:(?<pfx>wu|wo|warmed up with|working is)\s+)?(?:added\s+)?\(?\s*(?<p>(?:{CT}|{N})(?:\s*\+?\s*(?:{CT}|{N}))*)\s*\)?\s*(?:kg\s*)?{SIDE}\b(?:\s*[;,]?\s*(?<bar>{N})(?:/{N})?\s*(?:kg\s*)?bar)?"#)
        barLine = rx(#"^(?<p>{N}(?:\s*\+?\s*{N})*)\s*;\s*(?<bar>{N})\s*bar"#)
        pin = rx(#"(?<![\d.(])(?<s>{N})(?:\s*\+?\s*(?<a>{N}))?(?:\s+|\s*\+\s*)\(\s*(?<p>{N}(?:\s*\+?\s*[a-z]?{N})*)\s*(?:(?<pin2>{PW})\s*)?(?:\)|$)\s*(?:(?<pin>{PWT})(?<pinjunk>[a-z]?))?"#)
        pinLoose = rx(#"^(?<s>{N})(?<rest>(?:\s*\+\s*{N}\s*(?:{PW})?)*)\s*\+?\s*\(?\s*(?<pin>{PW})\s*\)?$|^(?<s2>{N})\s*\+\s*(?<p2>{N})\s*\(\s*(?<pin2>{PW})\s*\)$|^(?<s3>{N})(?<rest3>(?:\s*\+\s*{N})*)\s*\+\s*\(\s*(?<p3>{N}(?:\s*\+\s*{N})*)\s*(?<pin3>{PW})\s*\)$"#)
        db = rx(#"^(?<d>{N})\s*kg\s*(?:db|dbs)(?:\s*\+\s*(?<x>{N})\s*kg\s*weight)?|^(?<n>\d)x\s?(?<d2>{N})\s*dbs"#)
        count = rx(#"^(?<p>{CT}(?:\s*\+?\s*(?:{CT}|{N}))*|{N}(?:\s*\+?\s*(?:{N}))*\s*\+?\s*{CT}(?:\s*\+?\s*(?:{CT}|{N}))*)\s*(?<u>kg|{PW})?(?=\s|$)"#)
        sum = rx(#"^(?<s>{N})(?<rest>(?:\s*\+\s*{N}\s*(?:{PW}|kg)?)+)\s*(?:\(?(?:{PW})\)?)?(?=\s|$)"#)
        plus = rx(#"^:?\s*\+\s*(?<rest>{N}\s*(?:kg)?(?:\s*\+\s*{N}\s*(?:kg)?)*)"#)
        spaced = rx(#"^(?<s>{N})(?<rest>(?:\s+{N})+)(?:\s*(?<pin>{PW}))?(?=\s*$)"#)
        single = rx(#"^(?<s>{N})\s*(?:kg)?\s*(?:db)?$"#)
        lead = rx(#"^(?<s>{N})(?=\s+\S)"#)
        countTerm = rx(#"(?<c>\d{1,2})\s?\(\s*(?<cp>{N}(?:\s*\+\s*{N})*)\s*\)|(?<x>\d{1,2})\s?x\s?(?<xp>{N})|(?<n>{N})"#)
        countLead = rx(#"^(?<b>{N})\s*\+?\s*(?={CT})"#)
        countParen = rx(#"\d\s?[(x]"#)
        digitParen = rx(#"^\d\("#)
        pinWord = Rx(#"(?<![a-z])(?:"# + pw + #")(?![a-z])"#)

        setIndex = rx(#"^(?:set\s*)?(?<i>\d)\s*[:;]\s*|^(?<d>d|left|right)\s*:\s*"#)
        bareRirLine = rx(#"^-?[01](?:\s*-\s*[12])?$"#)
        bareRir = rx(#"^(?<a>-?{N})(?:\s*-\s*(?<b>{N}))?(?=\s|$|,)(?!\s?(?:[lr]\b|left|right|reps?\b|on\b))"#)
        bareNotLoad = rx(#"^-?{N}\s*(?:\+|\(|a side|kg)"#)
        leadStop = rx(#"^(?:is|kg|was|reps?|sets?|x|plate|apart|holes?|might|on|shows|kept|keeps|for|if|stacking|maybe)\b"#)
        leadLoad = rx(#"^{N}\s*(?:\+|\()"#)

        sides2 = rx(#"(?<![\w.])(?<a>\d+(?:-\d+)?)\??\s?(?<as>[lr])(?:[a-z](?=\s|$|\d))?\s*,?\s*(?<b>\d+(?:-\d+)?)\s?(?<bs>[lr])(?:[pqzb])?(?![a-z])"#)
        sides2b = rx(#"(?<![a-z])(?<as>[lr])\s?(?<a>\d+)\s*,?\s*(?<bs>[lr])\s?(?<b>\d+)\b|(?<a2>\d+) (?:on )?(?<as2>left|right)\s*,?\s*(?<b2>\d+) (?:on )?(?<bs2>left|right)"#)
        rir = rx(#"(?<![\w.])(?<a>-?{N}|\d/\d)(?:\s*(?:-|to)\s*(?<b>{N})?)?\s?rir(?![a-z])"#)
        rirR = rx(#"(?<![\w.])(?<a>-?{N})\s*-\s*(?<b>{N})?\s?r(?![a-z])"#)
        side1 = rx(#"(?<![\w.])(?<a>\d+(?:-\d+)?)\s?(?<as>[lr])(?:[pqzb])?(?![a-z])"#)
        fail = rx(#"\bfail(?:ure|ed)?\b"#)
        counters = rules.counters.isEmpty ? nil : {
            let w = Grammar.alt(rules.counters)
            return rx(#"(?<![\w.]){N}(?:-{N})?\s?(?:W)(?![a-z])|\+\s?\d\s?(?:W)(?![a-z])"#.replacingOccurrences(of: "W", with: w))
        }()

        let names = Grammar.alt(Grammar.settingWords + rules.settingWords)
        let at = #"(?:at|on|sits? on|sit|set at)"#
        let show = #"(?:shows|show|showing|see)"#
        func srx(_ p: String) -> Rx {
            rx(p.replacingOccurrences(of: "NAMES", with: names).replacingOccurrences(of: "AT", with: at)
                .replacingOccurrences(of: "SHOW", with: show))
        }
        shows = [
            srx(#"(?:(?<name>NAMES)\s)?AT\s?(?<pos>\d+)\s*(?:holes)?\s*,?\s*SHOW\s?(?<lab>{N})"#),
            srx(#"(?:(?<name>NAMES)\s)?(?:shows|show|showing)\s?(?<lab>{N})\s*(?:holes?)?\s*,?\s*(?:at|on)\s?(?<pos>\d+)"#),
            srx(#"(?:(?<name>NAMES)\s)?(?<![\d.])(?<pos>\d+)\s+shows\s+(?<lab>{N})"#),
            srx(#"(?:(?<name>NAMES)\s)?(?:shows|show|showing)\s?(?<lab>{N})(?:\s*(?:holes?))?"#),
        ]
        named = srx(#"(?<name>NAMES)\s*(?:@|at|on|is|=)?\s*(?<val>\d+)(?:\s*(?:st|nd|rd|th))?(?![\d.]|\s?(?:kg|a side|rir))"#)
        unnamed = rx(#"^(?:set |sit |kept |keep it )?(?:at|on|@)\s?(?<val>\d+)$|(?:under (?<u>\d+) (?:@|at) ?(?<v2>\d+))"#)
        adjust = rx(#"^(?<n>\d)\s?(?<d>up|down|back)(?![a-z])"#)
        stacks = rx(#"(?<![\d.])(?:\d|one|both|two)\s(?:(?:upstairs|downstairs)\s)?(?:cable\s)?stacks?|(?:uses|using|use)\s(?:\d|both|two)\sstacks|(?:left|right) stack"#)
        location = rx(#"(?<![a-z])(?:up|down)\s?\d\s?[ab](?:\s*[,.]\s*[ab])?(?![a-z])|^(?:up|down)!?$|(?<![a-z])(?:upstairs|downstairs)(?![a-z])|^[ab]$|(?<![\d.])\d (?:upstairs|downstairs)(?![a-z])|(?:upstairs|downstairs) \d(?![\d.])"#)
        locationDigit = rx(#"(?<![\d.])\d (?=$)"#)
        keep = (Grammar.keepPhrases + rules.keep).map { rx($0) }
        onLeg = rx(#"{N} on leg"#)
        inline = rx(#"(?<![\w.]){N}\s*(?:\+\s*)?(?:{N}\s*)?\+?\s*\("#)
        perSideAdd = rx(#"(?:added\s+)?(?:(?<n>\d)x\s?)?(?<v>{N})\s*(?:kg)?\s*(?:a|each|per)\s*side"#)
        plan = rx(([#"(?:drop|lower|reduce|raise|back|go|move|moved|increase|change|up|upped|started|try|down)\w*(?: \w+){0,3}? (?:to|by|at|for) (?:like |around |a )?(?:\+ ?)?\(?{N}[^a-z]*(?:kg|a side|shows \d+)?"#,
                    #"(?:try|go|get|for|will get|try for) \d(?: \w+)?"#, #"next time \w+ \d+"#, #"(?:up|drop) weight \d+"#]
                   + rules.plans).joined(separator: "|"))
    }

    /// Plain English names of machine settings.
    static let settingWords = ["seat", "seat back", "back", "bench", "incline", "pad", "handles", "handle", "lever", "arm", "level"]

    /// Plain English positions that stay in the note as written.
    static let keepPhrases = [
        #"(?:seat|bench)\s(?:at|on)\s(?:the\s)?(?:bottom|lowest|top)"#,
        #"pressed down (?:into )?\d(?:st|nd|rd|th) (?:position|hole)"#,
        #"\d+ notch(?:es)? (?:back|from bottom)"#,
        #"\d+ holes?"#,
    ]

    /// `words` as one alternation, longest first so a longer phrase wins over its start.
    static func alt(_ words: [String]) -> String {
        let w = Array(Set(words.map { $0.lowercased() })).sorted { $0.count != $1.count ? $0.count > $1.count : $0 < $1 }
        return w.isEmpty ? "(?!)" : w.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
    }
}
