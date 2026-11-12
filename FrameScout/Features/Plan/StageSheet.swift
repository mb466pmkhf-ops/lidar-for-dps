import SwiftUI
import UIKit

/// Daylight through the windows (sun, sky, cloud) and a studio build (backdrop and floor) for one
/// location. The figures here come from a standard sky model, not from the location, so they are
/// labelled estimated (Docs/DECISIONS.md D-014).
struct StageSheet: View {
    @Binding var location: Location
    let plan: FloorPlan?
    let scan: ScanRecord?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                daylightSection
                if daylight.isOn == true { sunSection }
                studioSection
                if studio.backdrop != nil || studio.floor != nil { studioDetailSection }
            }
            .fsScreen()
            .navigationTitle("Daylight and studio set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Daylight

    private var daylight: DaylightSetup { location.daylight ?? DaylightSetup() }
    private func editDaylight(_ f: (inout DaylightSetup) -> Void) {
        var d = daylight
        f(&d)
        location.daylight = d
    }

    private var daylightSection: some View {
        Section {
            Toggle("Sun and sky through the windows", isOn: Binding(get: { daylight.isOn == true }, set: { v in editDaylight { $0.isOn = v } }))
                .tint(Theme.accent)
            if daylight.isOn == true {
                Picker("Sky", selection: Binding(get: { daylight.sky ?? .clear }, set: { v in editDaylight { $0.sky = v } })) {
                    ForEach(SkyKind.allCases) { k in Text(Stage.sky(k).label).tag(k) }
                }
            }
        } header: {
            Text("Daylight")
        } footer: {
            Text("Windows let in sky light, and sun where the beam reaches. Curtains are set on each window. Nothing outside the room (trees, buildings) is known, so real daylight is often lower.")
        }
    }

    private var sunSection: some View {
        let place = Stage.sunPlacement(location, scan: scan)
        let levels = Stage.daylightLevels(daylight.sky ?? .clear, elevation: place.elevation)
        let problem = Stage.clockProblem(location, scan: scan)
        return Section {
            Picker("Place the sun", selection: Binding(get: { daylight.fromClock == true }, set: { v in
                editDaylight { d in
                    d.fromClock = v
                    if v && d.time == nil { d.time = Date().timeIntervalSince1970.rounded() }
                }
            })) {
                Text("By hand").tag(false)
                Text("From date and time").tag(true)
            }
            .pickerStyle(.segmented)
            if daylight.fromClock == true {
                DatePicker("When", selection: Binding(get: { Date(timeIntervalSince1970: daylight.time ?? Date().timeIntervalSince1970) },
                                                      set: { v in editDaylight { $0.time = v.timeIntervalSince1970.rounded() } }))
                    .environment(\.timeZone, location.timeZone)
                if let problem {
                    Text(problem).font(.fsCaption).foregroundStyle(Theme.textSecondary)
                }
            }
            if !place.fromClock {
                angleRow("Comes from", value: daylight.sunBearing ?? Stage.defaultSunBearing, range: 0...359, suffix: "° on the plan") { v in
                    editDaylight { $0.sunBearing = v }
                }
                angleRow("Height", value: daylight.sunElevation ?? Stage.defaultSunElevation, range: -6...90, suffix: "° above the horizon") { v in
                    editDaylight { $0.sunElevation = v }
                }
            } else {
                LabeledContent("Sun", value: "\(Int(place.azimuth?.rounded() ?? 0))° from north, \(Int(place.elevation.rounded()))° up")
            }
            figureRow("Sun, square on", lux: levels.directNormal)
            figureRow("Sky on open ground", lux: levels.skyHorizontal)
        } header: {
            Text("Sun")
        } footer: {
            Text(place.elevation <= 0 ? "The sun is down. Only twilight sky, fading to nothing 6° below the horizon."
                 : "Outdoor levels from a standard clear, hazy or overcast sky. The readings inside use these through the glass.")
        }
    }

    // MARK: Studio

    private var studio: StudioSetup { location.studio ?? StudioSetup() }
    private func editStudio(_ f: (inout StudioSetup) -> Void) {
        var s = studio
        f(&s)
        location.studio = (s.backdrop == nil && s.floor == nil) ? nil : s
    }

    private var studioSection: some View {
        Section {
            Picker("Backdrop", selection: Binding(get: { studio.backdrop }, set: { v in
                editStudio { s in
                    s.backdrop = v
                    s.colour = nil
                    if v == nil { s.wallID = nil; s.moreWalls = nil }
                    // Keep the walls, but let each piece take the new backdrop's own size.
                    s.width = nil
                    s.height = nil
                    s.offset = nil
                    s.moreWalls = s.moreWalls.map { $0.map { BackdropWall(wallID: $0.wallID) } }
                }
            })) {
                Text("None").tag(String?.none)
                Section("Cyc") { ForEach(Stage.backdrops.filter { $0.kind == .cyc }) { b in Text(b.label).tag(String?.some(b.id)) } }
                Section("Paper roll") { ForEach(Stage.backdrops.filter { $0.kind == .paper }) { b in Text(b.label).tag(String?.some(b.id)) } }
                Section("Screen") { ForEach(Stage.backdrops.filter { $0.kind == .led }) { b in Text(b.label).tag(String?.some(b.id)) } }
            }
            Picker("Floor", selection: Binding(get: { studio.floor }, set: { v in editStudio { $0.floor = v; $0.floorColour = nil } })) {
                Text("As scanned").tag(String?.none)
                ForEach(Stage.floors) { f in Text(f.label).tag(String?.some(f.id)) }
            }
        } header: {
            Text("Studio set")
        } footer: {
            if let b = Stage.backdrop(studio.backdrop), !b.note.isEmpty { Text(b.note) }
        }
    }

    /// A wall the backdrop is on, as stored (the main wall first).
    private struct Part: Hashable { var wallID: UUID; var offset: Double?; var width: Double? }

    private func parts(_ layout: Stage.BackdropLayout?) -> [Part] {
        guard let main = layout?.pieces.first else { return [] }
        let onPlan = Set(layout?.pieces.map(\.wall.id) ?? [])
        return [Part(wallID: main.wall.id, offset: studio.offset, width: studio.width)]
            + (studio.moreWalls ?? []).filter { onPlan.contains($0.wallID) }.map { Part(wallID: $0.wallID, offset: $0.offset, width: $0.width) }
    }

    private func saveParts(_ next: [Part]) {
        guard let main = next.first else { return }
        editStudio { s in
            s.wallID = main.wallID
            s.offset = main.offset
            s.width = main.width
            let more = next.dropFirst().map { BackdropWall(wallID: $0.wallID, offset: $0.offset, width: $0.width) }
            s.moreWalls = more.isEmpty ? nil : Array(more)
        }
    }

    private var studioDetailSection: some View {
        let info = Stage.backdrop(studio.backdrop)
        let floor = Stage.floor(studio.floor)
        let layout = Stage.backdropLayout(location, plan: plan)
        let placement = layout?.pieces.first
        let walls = (plan?.walls ?? []).filter { $0.length > 0.5 }
        let current = parts(layout)
        let names = plan.map(Stage.wallNames) ?? [:]
        func name(_ id: UUID) -> String { names[id] ?? "Wall" }
        return Section {
            if let info {
                if walls.count > 1, let placement {
                    ForEach(walls) { w in
                        let on = current.contains { $0.wallID == w.id }
                        let corner = !on && current.contains { p in walls.first { $0.id == p.wallID }.map { Stage.wallsTouch(w, $0) } ?? false }
                        Toggle(isOn: Binding(get: { on }, set: { v in
                            if v { saveParts(current + [Part(wallID: w.id)]) }
                            else if current.count > 1 { saveParts(current.filter { $0.wallID != w.id }) }
                        })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(name(w.id)), \(UnitsFormatter.distance(w.length))")
                                if studio.wallID == nil && w.id == placement.wall.id {
                                    Text("Faces the camera").font(.fsCaption).foregroundStyle(Theme.textSecondary)
                                } else if corner {
                                    Text(info.kind == .cyc ? "Makes a corner: the cyc curves round it" : "Makes a corner").font(.fsCaption).foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                        .disabled(on && current.count == 1)
                    }
                }
                if info.pickColour {
                    ColorPicker("Colour", selection: Binding(get: { Color(hex: studio.colour ?? info.colour) },
                                                             set: { c in editStudio { $0.colour = UIColor(c).hexString } }),
                                supportsOpacity: false)
                }
                if let placement {
                    sliderRow("Height", value: placement.height, range: 0.5...max(0.51, placement.wall.bottom + placement.wall.height), unit: "m") { v in editStudio { $0.height = v } }
                    ForEach(Array(current.enumerated()), id: \.element.wallID) { i, part in
                        let piece = layout?.pieces.first { $0.wall.id == part.wallID }
                        let wallLength = piece?.wall.length ?? placement.wall.length
                        let width = min(wallLength, max(0.5, part.width ?? Stage.defaultBackdropWidth(info.kind, wallLength: wallLength)))
                        let put: (Part) -> Void = { p in var next = current; next[i] = p; saveParts(next) }
                        if current.count > 1 { Text(name(part.wallID)).font(.fsCaption).foregroundStyle(Theme.textSecondary) }
                        sliderRow("Width", value: width, range: 0.5...max(0.51, wallLength), unit: "m") { v in var p = part; p.width = v; put(p) }
                        if width < wallLength - 0.05 {
                            let slack = (wallLength - width) / 2
                            sliderRow("Along the wall", value: part.offset ?? piece?.offset ?? 0, range: -slack...slack, unit: "m") { v in var p = part; p.offset = v; put(p) }
                        }
                    }
                }
                if info.kind == .led {
                    sliderRow("Brightness", value: studio.nits ?? Stage.ledDefaultNits, range: Stage.ledNitsRange, unit: "nits", digits: 0) { v in
                        editStudio { $0.nits = v.rounded() }
                    }
                    sliderRow("White point", value: studio.kelvin ?? 5600, range: 2700...10000, unit: "K", digits: 0) { v in
                        editStudio { $0.kelvin = (v / 100).rounded() * 100 }
                    }
                    HStack {
                        Text("Light from the wall").font(.fsCaption)
                        Spacer()
                        ProvenanceBadge(provenance: .estimated)
                    }
                }
                LabeledContent("Reflects", value: "about \(Int((info.reflectance * 100).rounded())) %")
            }
            if let floor, floor.pickColour {
                ColorPicker("Floor colour", selection: Binding(get: { Color(hex: studio.floorColour ?? floor.colour) },
                                                               set: { c in editStudio { $0.floorColour = UIColor(c).hexString } }),
                            supportsOpacity: false)
            }
            if let floor {
                LabeledContent("Floor reflects", value: "about \(Int((floor.reflectance * 100).rounded())) %")
            }
        } header: {
            Text("Set details")
        } footer: {
            Text(info?.kind == .led
                 ? "The LED wall counts as a light in the readings, at the brightness you set. Reflections from the backdrop and floor are not added: there is no bounce."
                 : "Backdrop and floor change the picture only. Reflections are not added to the readings: there is no bounce.")
        }
    }

    // MARK: Rows

    private func figureRow(_ label: String, lux: Double) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(LuxFormat.lux(lux)).monospacedDigit().foregroundStyle(Theme.textSecondary)
            ProvenanceBadge(provenance: .estimated)
        }
    }

    private func angleRow(_ label: String, value: Double, range: ClosedRange<Double>, suffix: String, set: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text("\(Int(value.rounded()))\(suffix)").monospacedDigit().foregroundStyle(Theme.textSecondary)
            }
            Slider(value: Binding(get: { min(max(value, range.lowerBound), range.upperBound) }, set: { set($0.rounded()) }), in: range)
        }
    }

    private func sliderRow(_ label: String, value: Double, range: ClosedRange<Double>, unit: String, digits: Int = 1,
                           set: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text("\(String(format: "%.\(digits)f", value)) \(unit)").monospacedDigit().foregroundStyle(Theme.textSecondary)
            }
            Slider(value: Binding(get: { min(max(value, range.lowerBound), range.upperBound) }, set: set), in: range)
        }
    }
}

// MARK: Hex colours

extension UIColor {
    /// "#rrggbb" → colour; anything else → mid grey.
    convenience init(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let v = s.count == 6 ? UInt32(s, radix: 16) : nil
        let n = v ?? 0x808080
        self.init(red: CGFloat((n >> 16) & 0xFF) / 255, green: CGFloat((n >> 8) & 0xFF) / 255, blue: CGFloat(n & 0xFF) / 255, alpha: 1)
    }

    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        func c(_ x: CGFloat) -> Int { Int((min(1, max(0, x)) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", c(r), c(g), c(b))
    }
}

extension Color {
    init(hex: String) { self.init(UIColor(hex: hex)) }
}
