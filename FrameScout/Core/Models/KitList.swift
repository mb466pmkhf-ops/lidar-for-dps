import Foundation

/// The kit list a gaffer works from: units, modifiers, gels, grip and stands, counted from the plan,
/// plus the estimated power. Same rules as web/src/model/kit.ts: keep both in step.
struct KitList: Equatable {
    struct Line: Equatable { var qty: Int; var item: String }

    var units: [Line] = []
    var modifiers: [Line] = []
    var gels: [Line] = []
    var grip: [Line] = []
    var stands: [Line] = []
    /// Estimated draw of the units that are on, at their set output (W). Estimated.
    var drawNow: Double = 0
    /// Rated power of every unit on the plan, on or off: what to plan circuits for (W).
    var drawRated: Double = 0

    private static func count(_ items: [String]) -> [Line] {
        var order: [String] = []
        var n: [String: Int] = [:]
        for i in items { if n[i] == nil { order.append(i) }; n[i, default: 0] += 1 }
        return order.map { Line(qty: n[$0]!, item: $0) }
            .sorted { $0.qty != $1.qty ? $0.qty > $1.qty : $0.item.localizedStandardCompare($1.item) == .orderedAscending }
    }

    init(lights: [LightFixture]) {
        var units: [String] = [], modifiers: [String] = [], gels: [String] = [], grip: [String] = [], stands: [String] = []
        for l in lights {
            let support = l.supportValue
            if support != .none && support != .floor { for _ in 0..<l.gripStandCount { stands.append(support.label) } }
            if GripCatalog.gripKinds.contains(l.kind) {
                grip.append(l.gripLabel.isEmpty ? l.kind.label : l.gripLabel)
                continue
            }
            guard l.kind.emits else { continue }
            let p = l.profile
            units.append(p.name)
            if let m = l.modifierItem, m.id != p.defaultModifierID { modifiers.append(m.name) }
            gels += l.filterItems.map(\.name)
            drawRated += p.ratedPower
            if l.isOn { drawNow += l.photometrics.drawWatts }
        }
        self.units = Self.count(units); self.modifiers = Self.count(modifiers); self.gels = Self.count(gels)
        self.grip = Self.count(grip); self.stands = Self.count(stands)
    }

    static func amps(_ watts: Double, volts: Double) -> Double { watts / volts }

    /// Plain text, for a message or a call sheet. With `lights`, adds the circuits a UK 13 A socket and a US
    /// 15 A circuit would need; with `rates`, the user's own day rates for each line.
    func text(title: String, lights: [LightFixture] = [], rates: KitRates? = nil) -> String {
        var out = [title, ""]
        func section(_ name: String, _ lines: [Line]) {
            guard !lines.isEmpty else { return }
            out.append(name); out += lines.map { "  \($0.qty) × \($0.item)" }; out.append("")
        }
        section("Units", units)
        section("Modifiers", modifiers)
        section("Gels and diffusion", gels)
        section("Grip", grip)
        section("Stands", stands)
        if drawRated > 0 {
            out.append("Power (estimated)")
            out.append(String(format: "  Rated, all units: %d W (%.1f A at 230 V, %.1f A at 120 V)", Int(drawRated.rounded()),
                              Self.amps(drawRated, volts: 230), Self.amps(drawRated, volts: 120)))
            out.append("  As set, units on: \(Int(drawNow.rounded())) W")
        }
        if !lights.isEmpty {
            for id in ["uk13", "us15"] {
                let c = Self.circuitPlan(lights, supply: Self.supply(id: id))
                if c.circuits == 0 && c.tooBig.isEmpty { continue }
                out.append("  \(c.supply.label)s: \(c.circuits) separate circuit\(c.circuits == 1 ? "" : "s")"
                           + (c.tooBig.isEmpty ? "" : "; too big for one: \(c.tooBig.joined(separator: ", "))"))
            }
        }
        if let rates {
            let c = cost(rates)
            if !c.lines.isEmpty {
                out.append(""); out.append("Your day rates")
                out += c.lines.map { "  \($0.qty) × \($0.item) at \(KitRates.money($0.rate, rates.currency)) = \(KitRates.money($0.total, rates.currency))" }
                out.append("  Per day: \(KitRates.money(c.perDay, rates.currency))" + (c.missing.isEmpty ? "" : " (no rate for \(c.missing.joined(separator: ", ")))"))
            }
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    // MARK: Supplies and circuits

    /// A wall supply. Planned at 80 % of the rating, the usual allowance for a load left on for hours.
    struct Supply: Equatable, Identifiable { var id: String; var label: String; var volts: Double; var amps: Double }
    static let supplies: [Supply] = [
        Supply(id: "uk13", label: "UK 13 A socket", volts: 230, amps: 13),
        Supply(id: "eu16", label: "EU 16 A socket", volts: 230, amps: 16),
        Supply(id: "us15", label: "US 15 A circuit", volts: 120, amps: 15),
        Supply(id: "us20", label: "US 20 A circuit", volts: 120, amps: 20),
    ]
    static let continuousLoad = 0.8
    static func supply(id: String?) -> Supply { supplies.first { $0.id == id } ?? supplies[0] }
    /// Watts one circuit of this supply carries for hours.
    static func circuitWatts(_ s: Supply) -> Double { s.volts * s.amps * continuousLoad }

    struct CircuitPlan: Equatable {
        var supply: Supply
        /// Separate circuits the rated load needs, at least one.
        var circuits: Int
        /// Units too big for one of these circuits on their own: they need a bigger supply or a generator.
        var tooBig: [String]
    }

    /// Circuits for every unit on the plan at its rating (on or off), packed largest first so no unit is
    /// split across two circuits. An estimate: the venue's wiring decides what is really on each circuit.
    static func circuitPlan(_ lights: [LightFixture], supply: Supply) -> CircuitPlan {
        let cap = circuitWatts(supply)
        var loads: [(name: String, w: Double)] = []
        for l in lights where l.kind.emits && !GripCatalog.gripKinds.contains(l.kind) {
            let p = l.profile
            if p.ratedPower > 0 { loads.append((p.name, p.ratedPower)) }
        }
        var tooBig: [String] = []
        for x in loads where x.w > cap && !tooBig.contains(x.name) { tooBig.append(x.name) }
        var bins: [Double] = []
        // Stable sort, largest first, as the web does.
        let fits = loads.enumerated().filter { $0.element.w <= cap }.sorted { $0.element.w != $1.element.w ? $0.element.w > $1.element.w : $0.offset < $1.offset }
        for (_, x) in fits {
            if let i = bins.firstIndex(where: { $0 + x.w <= cap }) { bins[i] += x.w } else { bins.append(x.w) }
        }
        return CircuitPlan(supply: supply, circuits: max(bins.count, loads.isEmpty ? 0 : 1), tooBig: tooBig)
    }

    // MARK: Batteries

    /// Common V-mount and block sizes (Wh). 98 Wh packs stay under the 100 Wh airline carry-on limit.
    static let batterySizes: [Double] = [98, 150, 290]
    /// Share of a pack's rating a unit really gets (converter losses, the cut-off before empty).
    static let batteryUsable = 0.85
    /// Minutes a pack runs a unit drawing `watts`. Estimated.
    static func batteryMinutes(watts: Double, wh: Double) -> Double { watts > 0 ? (wh * batteryUsable / watts) * 60 : .infinity }
    /// "1 h 10 min", "25 min". Units above a few hundred watts aren't run on packs: "mains".
    static func runTimeLabel(watts: Double, wh: Double) -> String {
        guard watts > 0 else { return "" }
        if watts > 400 { return "mains" }
        let m = Int(batteryMinutes(watts: watts, wh: wh).rounded())
        return m >= 60 ? "\(m / 60) h \(m % 60) min" : "\(m) min"
    }

    // MARK: Your day rates

    struct CostLine: Equatable { var qty: Int; var item: String; var rate: Double; var total: Double }
    struct Cost: Equatable { var lines: [CostLine]; var perDay: Double; var missing: [String] }

    /// Each kit line priced at the user's rate. Lines without a rate are listed as missing, never guessed.
    func cost(_ rates: KitRates) -> Cost {
        var lines: [CostLine] = [], missing: [String] = []
        for l in units + modifiers + gels + grip + stands {
            guard let r = rates.items[l.item], r >= 0 else { missing.append(l.item); continue }
            lines.append(CostLine(qty: l.qty, item: l.item, rate: r, total: r * Double(l.qty)))
        }
        return Cost(lines: lines, perDay: lines.reduce(0) { $0 + $1.total }, missing: missing)
    }

    /// Every line in the list, in the order the sections are printed.
    var allLines: [Line] { units + modifiers + gels + grip + stands }
}

/// Day rates the user types in, per kit item, in their own currency. FrameScan has no prices of its own.
/// Kept on this device (UserDefaults `framescan.rates`, the web's localStorage) like My presets. The JSON
/// is the same on both, so Copy / Paste moves it between them: {"framescanRates":1,"currency":"£","items":{…}}.
struct KitRates: Equatable {
    var currency: String = "£"
    var items: [String: Double] = [:]

    static let defaultsKey = "framescan.rates"

    var json: String {
        let o: [String: Any] = ["framescanRates": 1, "currency": currency, "items": items]
        guard let d = try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys]) else { return "" }
        return String(decoding: d, as: UTF8.self)
    }

    init(currency: String = "£", items: [String: Double] = [:]) { self.currency = currency; self.items = items }

    private struct Stored: Decodable {
        /// An entry that isn't a number (or is negative) is dropped, not the whole file.
        struct Rate: Decodable {
            var value: Double?
            init(from decoder: Decoder) throws { value = try? decoder.singleValueContainer().decode(Double.self) }
        }
        var framescanRates: Int
        var currency: String?
        var items: [String: Rate]
    }

    /// The largest day rate kept: anything bigger is a slip of the finger, not a rate.
    static let maxRate = 1e9

    /// A typed day rate, with either decimal mark. The last mark is the decimal one ("12,50",
    /// "1,250.50", "1.250,50", "0.125"), except a mark used more than once, or a lone comma before
    /// exactly three digits after a whole part, which group thousands ("1.250.000", "1,250"). Same rule as the web.
    static func parse(_ text: String) -> Double? {
        let digit: (Character) -> Bool = { ("0"..."9").contains($0) }
        let t = text.filter { !$0.isWhitespace }
        guard t.contains(where: digit), t.allSatisfy({ digit($0) || $0 == "." || $0 == "," }) else { return nil }
        let marks = t.filter { $0 == "." || $0 == "," }
        var n = t
        if let lastIndex = t.lastIndex(where: { $0 == "." || $0 == "," }) {
            let mark = t[lastIndex]
            let after = t.distance(from: lastIndex, to: t.endIndex) - 1
            // A lone comma before exactly three digits groups thousands ("1,250"), unless the whole part
            // is zero ("0,125"). A lone point is always the decimal mark ("0.125", "1.250").
            let lead = t[..<lastIndex].drop { $0 == "0" }
            let grouping = marks.allSatisfy { $0 == mark } && (marks.count > 1 || (mark == "," && after == 3 && !lead.isEmpty))
            if grouping { n = t.filter(digit) }
            else { n = String(t[..<lastIndex].filter(digit)) + "." + String(t[t.index(after: lastIndex)...]) }
        }
        guard let v = Double(n), v.isFinite, v >= 0, v <= maxRate else { return nil }
        return v
    }

    init?(json text: String?) {
        guard let text, let d = text.data(using: .utf8),
              let o = try? JSONDecoder().decode(Stored.self, from: d), o.framescanRates == 1 else { return nil }
        var items: [String: Double] = [:]
        for (k, r) in o.items { if let x = r.value, x >= 0, x <= Self.maxRate { items[k] = x } }
        self.init(currency: o.currency.map { $0.count <= 4 ? $0 : "£" } ?? "£", items: items)
    }

    /// "£1,250", "£12.50": grouped, whole amounts without pence.
    static func money(_ v: Double, _ currency: String) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        let whole = v.rounded() == v
        f.minimumFractionDigits = whole ? 0 : 2
        f.maximumFractionDigits = 2
        return currency + (f.string(from: NSNumber(value: v)) ?? String(v))
    }
}
