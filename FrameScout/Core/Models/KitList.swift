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

    /// Plain text, for a message or a call sheet.
    func text(title: String) -> String {
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
        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }
}
