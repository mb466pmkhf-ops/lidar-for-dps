import Foundation

/// "Build from a listing": reads room sizes out of text copied from a studio or location website
/// ("Studio 2: 15m x 10m x 6m to grid, 1,600 sq ft, two windows, loading door 3m x 4m") and turns
/// them into a `DrawnRoom`. Mirrors `web/src/model/listing.ts` line for line; both run the cases in
/// `web/tests/fixtures/listings.json`. Nothing here is measured: every figure is copied from someone
/// else's description, so the room is saved as entered by hand (manual provenance).
enum ListingReader {
    enum FindingKind: String { case size, ceiling, area, windows, door, skipped }

    struct Finding: Hashable {
        var kind: FindingKind
        /// Plain words, e.g. "Room 15 × 10 m".
        var text: String
        /// The part of the listing it came from.
        var quote: String
    }

    struct Size: Hashable {
        var length: Double
        var width: Double
        var ceiling: Double?
        var quote: String
    }

    enum SizeSource: String { case listed, fromArea, squareFromArea, none }

    struct Reading: Hashable {
        /// Longer side (m).
        var length: Double?
        /// Shorter side (m).
        var width: Double?
        var ceiling: Double?
        /// Floor area (m²) when the listing gives one.
        var area: Double?
        var windows: Int?
        var door: Bool?
        var sizeSource: SizeSource = .none
        var findings: [Finding] = []
        /// Other room sizes in the listing (another studio, a second stage), largest first.
        var alternatives: [Size] = []

        /// One line on where the size came from, for under the preview.
        var sizeNote: String {
            switch sizeSource {
            case .listed: return "Sizes copied from the listing, not measured."
            case .fromArea: return "One side is worked out from the floor area in the listing."
            case .squareFromArea: return "The listing only gives a floor area, so this is a square of that area. Check the photos and set the real shape."
            case .none: return "No room size found in the text. Set the sizes yourself."
            }
        }

        /// The drawn room the listing describes. Anything the listing doesn't say keeps `base`.
        func room(base: DrawnRoom = DrawnRoom()) -> DrawnRoom {
            var r = base
            r.length = length ?? base.length
            r.width = width ?? base.width
            r.ceiling = ceiling ?? base.ceiling
            r.windows = windows ?? base.windows
            r.door = door ?? base.door
            return r.normalised
        }
    }

    // MARK: Tables (same as listing.ts)

    private enum Role { case ceiling, length, width }

    private static let foot = 0.3048, inch = 0.0254
    private static let lengthUnits: [String: Double] = [
        "m": 1, "metre": 1, "metres": 1, "meter": 1, "meters": 1, "mtr": 1, "mtrs": 1, "cm": 0.01, "mm": 0.001,
        "ft": foot, "feet": foot, "foot": foot, "'": foot, "in": inch, "inch": inch, "inches": inch, "\"": inch,
    ]
    private static let areaUnits: [String: Double] = ["sqm": 1, "sqft": foot * foot]
    private static let numberWords: [String: Double] = [
        "no": 0, "zero": 0, "a": 1, "an": 1, "one": 1, "single": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
    ]
    // Words that label the figure after them ("ceiling height 6m") or before them ("6m high").
    private static let beforeWords: [String: Role] = [
        "ceiling": .ceiling, "ceilings": .ceiling, "height": .ceiling, "headroom": .ceiling, "grid": .ceiling, "clearance": .ceiling,
        "length": .length, "width": .width, "depth": .width,
    ]
    private static let afterWords: [String: Role] = [
        "high": .ceiling, "tall": .ceiling, "grid": .ceiling, "ceiling": .ceiling, "ceilings": .ceiling, "headroom": .ceiling, "clear": .ceiling,
        "long": .length, "wide": .width, "deep": .width,
    ]
    private static let roomWords: Set<String> = ["studio", "stage", "room", "floor", "space", "dimensions", "dimension", "size", "overall",
                                                 "shooting", "area", "hall", "footprint", "internal", "set"]
    // A size in a clause with one of these is a door, a cyc or a side room, not the shooting space.
    private static let featureWords: Set<String> = ["door", "doors", "doorway", "entrance", "access", "shutter", "cyc", "cyclorama", "cove",
                                                    "infinity", "screen", "dressing", "makeup", "kitchen", "office", "lounge", "parking", "car",
                                                    "lift", "elevator", "window", "windows", "table", "backdrop", "green", "production",
                                                    "toilet", "toilets", "bathroom"]
    private static let doorWords: Set<String> = ["door", "doors", "doorway", "shutter", "entrance"]
    private static let noWindowPhrases = ["no windows", "no window", "windowless", "blackout", "no natural light", "no daylight"]

    private enum Token {
        case num(Double)
        case word(String)
        var word: String? { if case .word(let w) = self { return w } else { return nil } }
        var isNum: Bool { if case .num = self { return true } else { return false } }
    }

    private struct Group {
        var length: Double
        var width: Double
        var ceiling: Double?
        var quote: String
        var roomy: Bool
    }

    private struct Quantity {
        var value: Double
        var unit: String?
        var area: Bool
        var start: Int
        var end: Int
    }

    // MARK: Text

    private static func replace(_ s: String, _ pattern: String, _ template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        return re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
    }

    /// Lower case, one spelling for units and the "by" sign, so the tokeniser stays simple.
    static func normalise(_ text: String) -> String {
        var s = text.lowercased()
        s = replace(s, "[×✕✖]", " x ")
        s = replace(s, "[’′‘`]", "'")
        s = replace(s, "[”″“]", "\"")
        s = replace(s, "square\\s+(?:metres|meters|metre|meter|m)\\b", " sqm ")
        s = replace(s, "square\\s+(?:feet|foot|ft)\\b", " sqft ")
        s = replace(s, "sq\\.?\\s*(?:metres|meters|m)\\b\\.?", " sqm ")
        s = replace(s, "sq\\.?\\s*(?:feet|ft)\\b\\.?", " sqft ")
        s = replace(s, "m²|m2\\b", " sqm ")
        s = replace(s, "ft²|ft2\\b", " sqft ")
        // "12x8m", "12mx8m", "40'x30'": space out an x that sits between two sizes.
        s = replace(s, "([0-9'\"]|m|t)\\s*x(?=\\s*\\d)", "$1 x ")
        return s
    }

    /// Lines and sentences of the original text, so a quote reads as the listing wrote it.
    private static func clauses(_ text: String) -> [String] {
        let scalars = Array(text.unicodeScalars)
        var parts: [String] = []
        var current = String.UnicodeScalarView()
        for (i, c) in scalars.enumerated() {
            let nextIsSpaceOrEnd = i + 1 >= scalars.count || CharacterSet.whitespacesAndNewlines.contains(scalars[i + 1])
            if c == "\n" || c == ";" || c == "•" || c == "|" || (c == "." && nextIsSpaceOrEnd) {
                parts.append(String(current))
                current = String.UnicodeScalarView()
            } else {
                current.append(c)
            }
        }
        parts.append(String(current))
        return parts
            .map { $0.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
            .filter { !$0.isEmpty }
    }

    private static func quoteOf(_ clause: String) -> String {
        clause.count > 90 ? String(clause.prefix(87)) + "…" : clause
    }

    private static func tokenise(_ clause: String) -> [Token] {
        let c = Array(clause.unicodeScalars)
        func isDigit(_ i: Int) -> Bool { i < c.count && c[i] >= "0" && c[i] <= "9" }
        func isLetter(_ i: Int) -> Bool { i < c.count && c[i] >= "a" && c[i] <= "z" }
        func text(_ a: Int, _ b: Int) -> String { String(String.UnicodeScalarView(c[a..<b])) }
        var out: [Token] = []
        var i = 0
        while i < c.count {
            if isDigit(i) {
                var j = i
                while isDigit(j) { j += 1 }
                var digits = text(i, j)
                var value = Double(digits) ?? 0
                // "1,600" is sixteen hundred; "4,5" and "4.5" are four and a half.
                while j + 1 < c.count && (c[j] == "," || c[j] == ".") && isDigit(j + 1) {
                    var k = j + 1
                    while isDigit(k) { k += 1 }
                    let frac = text(j + 1, k)
                    if c[j] == "," && frac.count == 3 {
                        digits += frac
                        value = Double(digits) ?? 0
                    } else {
                        value = Double(digits + "." + frac) ?? 0
                        j = k
                        break
                    }
                    j = k
                }
                out.append(.num(value))
                i = j
            } else if isLetter(i) {
                var j = i
                while isLetter(j) { j += 1 }
                out.append(.word(text(i, j)))
                i = j
            } else {
                if c[i] == "'" || c[i] == "\"" { out.append(.word(String(Character(c[i])))) }
                i += 1
            }
        }
        return out
    }

    /// Numbers with their units, joining 12' 6" into one length. Values are metres or square metres.
    private static func quantities(_ tokens: [Token]) -> [Quantity] {
        var out: [Quantity] = []
        var i = 0
        while i < tokens.count {
            defer { i += 1 }
            guard case .num(let v) = tokens[i] else { continue }
            let unit = i + 1 < tokens.count ? tokens[i + 1].word : nil
            if let unit, let scale = areaUnits[unit] {
                out.append(Quantity(value: v * scale, unit: unit, area: true, start: i, end: i + 1))
                i += 1
                continue
            }
            if let unit, let scale = lengthUnits[unit] {
                var value = v * scale, end = i + 1
                if scale == foot, i + 3 < tokens.count, case .num(let inches) = tokens[i + 2],
                   let u2 = tokens[i + 3].word, lengthUnits[u2] == inch, inches < 12 {
                    value += inches * inch
                    end = i + 3
                }
                out.append(Quantity(value: value, unit: unit, area: false, start: i, end: end))
                i = end
                continue
            }
            out.append(Quantity(value: v, unit: nil, area: false, start: i, end: i))
        }
        return out
    }

    /// The label words next to a figure: before it (nearest first, up to 4) and after it (up to 3),
    /// never reaching past another number.
    private static func context(_ tokens: [Token], _ start: Int, _ end: Int) -> (before: [String], after: [String]) {
        var before: [String] = [], after: [String] = []
        var k = start - 1
        while k >= 0 && k >= start - 4 {
            guard let w = tokens[k].word else { break }
            before.append(w)
            k -= 1
        }
        k = end + 1
        while k < tokens.count && k <= end + 3 {
            guard let w = tokens[k].word else { break }
            after.append(w)
            k += 1
        }
        return (before, after)
    }

    /// What a lone figure is: "6m high" and "40 ft long" read the word after it first, then
    /// "ceiling height 6m" the word before.
    private static func role(_ ctx: (before: [String], after: [String])) -> Role? {
        for w in ctx.after { if let r = afterWords[w] { return r } }
        for w in ctx.before { if let r = beforeWords[w] { return r } }
        return nil
    }

    private static func word(_ tokens: [Token], _ i: Int) -> String? { i >= 0 && i < tokens.count ? tokens[i].word : nil }
    static func round2(_ v: Double) -> Double { (v * 100).rounded() / 100 }
    /// "15", "18.29": like JavaScript's String(number) for these values.
    static func fmt(_ v: Double) -> String {
        let r = round2(v)
        return r == r.rounded() && abs(r) < 1e15 ? String(Int(r)) : String(r)
    }

    // MARK: Reading

    /// Reads room sizes, ceiling, area, windows and doors out of free text.
    static func read(_ text: String) -> Reading {
        var findings: [Finding] = []
        var groups: [Group] = []
        var length: Double?, width: Double?, ceiling: Double?, area: Double?
        var windows: Int?, door: Bool?
        func drop(_ kind: FindingKind) { if let i = findings.firstIndex(where: { $0.kind == kind }) { findings.remove(at: i) } }

        let whole = normalise(text)
        if noWindowPhrases.contains(where: { whole.contains($0) }) { windows = 0 }

        for original in clauses(text) {
            let clause = normalise(original)
            let tokens = tokenise(clause)
            let words = Set(tokens.compactMap(\.word))
            let clauseFeature = !words.isDisjoint(with: featureWords)
            let clauseRoomy = !words.isDisjoint(with: roomWords)
            let quote = quoteOf(original)
            let qs = quantities(tokens)
            var used = Set<Int>()

            if door == nil && !words.isDisjoint(with: doorWords) {
                door = true
                findings.append(Finding(kind: .door, text: "A door", quote: quote))
            }
            // "two windows", "3 large windows", "a single window".
            for i in tokens.indices {
                guard let w = tokens[i].word, w == "window" || w == "windows" else { continue }
                var back = 1
                while back <= 2 && i - back >= 0 {
                    defer { back += 1 }
                    let n: Double?
                    switch tokens[i - back] {
                    case .num(let v): n = v
                    case .word(let label): n = numberWords[label]
                    }
                    guard let n, n == n.rounded(), n <= 20 else { continue }
                    let count = Int(n)
                    if windows == nil || (windows == 0 && count > 0) {
                        windows = count
                        drop(.windows)
                        findings.append(Finding(kind: .windows, text: count == 1 ? "1 window" : "\(count) windows", quote: quote))
                    }
                    break
                }
            }

            // Sizes written as A x B (x C), with the unit on each number or only on the last.
            var i = 0
            while i < qs.count {
                defer { i += 1 }
                if qs[i].area { continue }
                var j = i
                while j + 1 < qs.count && j - i < 2 {
                    let sep = word(tokens, qs[j].end + 1)
                    if (sep == "x" || sep == "by") && qs[j + 1].start == qs[j].end + 2 && !qs[j + 1].area { j += 1 } else { break }
                }
                if j == i { continue }
                let run = Array(qs[i...j])
                let first = i
                i = j
                guard let unit = run.last(where: { $0.unit != nil })?.unit else { continue }
                let scale = lengthUnits[unit] ?? 1
                let vals = run.map { $0.unit != nil ? $0.value : $0.value * scale }
                for k in first...j { used.insert(k) }
                let a = max(vals[0], vals[1]), b = min(vals[0], vals[1])
                let h: Double? = vals.count == 3 ? vals[2] : nil
                let label = "\(fmt(vals[0])) × \(fmt(vals[1]))\(h.map { " × " + fmt($0) } ?? "") m"
                let ctx = context(tokens, run[0].start, run[run.count - 1].end)
                let localFeature = ctx.before.contains { featureWords.contains($0) }
                let localRoomy = ctx.before.contains { roomWords.contains($0) }
                if localFeature || (clauseFeature && !clauseRoomy && !localRoomy) {
                    findings.append(Finding(kind: .skipped, text: "Not the room: \(label)", quote: quote))
                    continue
                }
                if b < 1.5 || a > 300 {
                    findings.append(Finding(kind: .skipped, text: "Too small or large for a room: \(label)", quote: quote))
                    continue
                }
                let ceil: Double? = h.flatMap { $0 >= 1.8 && $0 <= 40 ? $0 : nil }
                groups.append(Group(length: a, width: b, ceiling: ceil, quote: quote, roomy: localRoomy || clauseRoomy))
            }

            // Single labelled figures: "ceiling height 6m", "7 m to grid", "length 20m", "1,600 sq ft".
            for (i, q) in qs.enumerated() {
                if used.contains(i) || q.unit == nil { continue }
                let ctx = context(tokens, q.start, q.end)
                // "Loading door 4m high" is the door. An area's unit already says what it is, so only the words before count.
                if ctx.before.contains(where: { featureWords.contains($0) }) || (!q.area && ctx.after.contains(where: { featureWords.contains($0) })) { continue }
                if q.area {
                    if area == nil || q.value > area! {
                        area = q.value
                        drop(.area)
                        findings.append(Finding(kind: .area, text: "Floor area \(fmt(q.value)) m²", quote: quote))
                    }
                    continue
                }
                switch role(ctx) {
                case .ceiling? where ceiling == nil && q.value >= 1.8 && q.value <= 40:
                    ceiling = q.value
                    findings.append(Finding(kind: .ceiling, text: "Ceiling \(fmt(q.value)) m", quote: quote))
                case .length? where length == nil && q.value >= 1.5:
                    length = q.value
                    findings.append(Finding(kind: .size, text: "Length \(fmt(q.value)) m", quote: quote))
                case .width? where width == nil && q.value >= 1.5:
                    width = q.value
                    findings.append(Finding(kind: .size, text: "Width \(fmt(q.value)) m", quote: quote))
                default:
                    break
                }
            }
        }

        // The room is the biggest size named as the studio or space; otherwise the biggest size at all.
        let roomy = groups.filter { $0.roomy }
        // Stable sort, like Array.prototype.sort, so equal sizes keep the listing's order.
        let ranked = (roomy.isEmpty ? groups : roomy).enumerated()
            .sorted { x, y in
                let ax = x.element.length * x.element.width, ay = y.element.length * y.element.width
                return ax != ay ? ax > ay : x.offset < y.offset
            }
            .map(\.element)
        var source = SizeSource.none
        if let best = ranked.first {
            length = best.length
            width = best.width
            source = .listed
            if let c = best.ceiling { ceiling = c; drop(.ceiling) }
            let high = best.ceiling.map { ", \(fmt($0)) m high" } ?? ""
            findings.insert(Finding(kind: .size, text: "Room \(fmt(best.length)) × \(fmt(best.width)) m\(high)", quote: best.quote), at: 0)
        } else if length != nil && width != nil {
            source = .listed
        } else if let area, let known = length ?? width {
            let other = area / known
            length = max(known, other)
            width = min(known, other)
            source = .fromArea
        } else if let area, area >= 2.25 {
            length = area.squareRoot()
            width = length
            source = .squareFromArea
        } else {
            length = nil
            width = nil
        }
        if let l = length, let w = width, w > l { length = w; width = l }

        var out = Reading()
        out.length = length.map(round2)
        out.width = width.map(round2)
        out.ceiling = ceiling.map(round2)
        out.area = area.map(round2)
        out.windows = windows
        out.door = door
        out.sizeSource = source
        out.findings = findings
        out.alternatives = ranked.dropFirst().prefix(4).map {
            Size(length: round2($0.length), width: round2($0.width), ceiling: $0.ceiling.map(round2), quote: $0.quote)
        }
        return out
    }
}
