import SwiftUI
import UIKit

/// The kit list with the power it needs: separate circuits on the chosen wall supply, how long a
/// battery pack runs each unit, and the user's own day rates. Circuits and run times are estimates;
/// the rates are whatever the user typed (FrameScan has no prices of its own). Same figures as the web
/// planner's print sheet (web/src/ui/PlanSheet.tsx).
struct KitSheet: View {
    let lights: [LightFixture]
    let onShare: () -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("framescan.power.supply") private var supplyID = "uk13"
    @AppStorage("framescan.power.pack") private var pack = 98.0
    @AppStorage(KitRates.defaultsKey) private var ratesText = ""
    @State private var note = ""
    /// What's typed in each rate field, so "12." stays as typed until the next digit.
    @State private var drafts: [String: String] = [:]

    private var kit: KitList { KitList(lights: lights) }
    private var rates: KitRates { KitRates(json: ratesText) ?? KitRates() }
    private func setRates(_ r: KitRates) { ratesText = r.json }

    var body: some View {
        NavigationStack {
            Form {
                powerSection
                packSection
                ratesSection
                Section {
                    Button { onShare() } label: { Label("Share kit list", systemImage: "square.and.arrow.up") }
                } footer: {
                    Text("The shared list includes circuits for a UK 13 A socket and a US 15 A circuit, and your day rates.")
                }
            }
            .fsScreen()
            .navigationTitle("Kit, power and rates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Power

    private var powerSection: some View {
        let supply = KitList.supply(id: supplyID)
        let plan = KitList.circuitPlan(lights, supply: supply)
        return Section {
            Picker("Wall supply", selection: $supplyID) {
                ForEach(KitList.supplies) { s in Text(s.label).tag(s.id) }
            }
            LabeledContent("Rated, all units", value: "\(Int(kit.drawRated.rounded())) W")
            LabeledContent("Separate circuits", value: "≈ \(plan.circuits)")
            if !plan.tooBig.isEmpty {
                Label("Too big for one: \(plan.tooBig.joined(separator: ", ")). Needs a bigger supply or a generator.", systemImage: "exclamationmark.triangle")
                    .font(.fsCaption)
            }
        } header: {
            Text("Power")
        } footer: {
            Text("Estimated: every unit at full, each circuit loaded to 80 % of its rating, no unit split across two. The venue's wiring decides what is really on each circuit.")
        }
    }

    private var packSection: some View {
        let units = lights.filter { $0.kind.emits && !GripCatalog.gripKinds.contains($0.kind) }
        return Section {
            Picker("Pack", selection: $pack) {
                ForEach(KitList.batterySizes, id: \.self) { wh in Text("\(Int(wh)) Wh").tag(wh) }
            }
            ForEach(units) { l in
                LabeledContent(l.name, value: KitList.runTimeLabel(watts: l.profile.ratedPower, wh: pack))
            }
        } header: {
            Text("On a battery pack")
        } footer: {
            Text("Estimated at full output with 85 % of the pack usable. Dimmed units run longer. Units over 400 W are shown as mains.")
        }
    }

    // MARK: Rates

    private var ratesSection: some View {
        Section {
            TextField("Currency", text: Binding(get: { rates.currency }, set: { v in var r = rates; r.currency = String(v.prefix(4)); setRates(r) }))
            ForEach(kit.allLines, id: \.item) { line in
                HStack {
                    Text("\(line.qty) × \(line.item)").font(.fsBody)
                    Spacer()
                    TextField("Day rate", text: rateBinding(line.item))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 110)
                }
            }
            let cost = kit.cost(rates)
            if !cost.lines.isEmpty {
                LabeledContent("Per day", value: KitRates.money(cost.perDay, rates.currency))
                    .font(.fsBodyStrong)
            }
            HStack {
                Button("Copy rates") { UIPasteboard.general.string = rates.json; note = "Rates copied" }
                    .buttonStyle(.borderless)
                Spacer()
                Button("Paste rates") {
                    if let r = KitRates(json: UIPasteboard.general.string) {
                        var merged = rates; merged.currency = r.currency
                        merged.items.merge(r.items) { _, new in new }
                        drafts = [:]; setRates(merged); note = "Rates pasted"
                    } else { note = "Nothing to paste: copy rates from FrameScan first" }
                }
                .buttonStyle(.borderless)
            }
            if !note.isEmpty { Text(note).font(.fsCaption).foregroundStyle(.secondary) }
        } header: {
            Text("Your day rates")
        } footer: {
            Text("Type what you pay a day for each item, from your rental house or your own kit. They stay on this iPhone. Items left blank are listed as having no rate.")
        }
    }

    private func rateBinding(_ item: String) -> Binding<String> {
        Binding(get: {
            if let d = drafts[item] { return d }
            guard let v = rates.items[item] else { return "" }
            return v.rounded() == v ? String(Int(v)) : String(v)
        }, set: { text in
            drafts[item] = text
            var r = rates
            let v = Double(text.replacingOccurrences(of: ",", with: "."))
            if let v, v >= 0, v.isFinite { r.items[item] = v } else { r.items.removeValue(forKey: item) }
            setRates(r)
        })
    }
}
