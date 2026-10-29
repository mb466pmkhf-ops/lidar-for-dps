import SwiftUI

/// Bottom panel for a stand-in person: type, height, build, skin tone and posture in one place.
struct CharacterPanel: View {
    let character: PrevisCharacter
    var reading: (lux: Double, stops: Double)?
    var exposure = ExposureSettings()
    let update: (@escaping (inout PrevisCharacter) -> Void) -> Void
    var onAim: () -> Void
    var onDuplicate: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                TextField("Name", text: Binding(get: { character.name }, set: { v in update { $0.name = v } }))
                    .font(.fsHeadline)
                Spacer()
                Text(character.summary).font(.fsCaption).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            CharacterFields(character: character, update: update)
            if let reading {
                HStack {
                    Text("FACE").font(.fsLabel).tracking(Theme.tracking).foregroundStyle(Theme.textTertiary)
                    Text("≈ \(LuxFormat.lux(reading.lux)) · \(ExposureSettings.stopsDelta(reading.stops)) at \(ExposureSettings.stopLabel(exposure.tStop))")
                        .font(.fsMono)
                    Spacer()
                    ProvenanceBadge(provenance: .estimated)
                }
                .accessibilityElement(children: .combine)
            }
            HStack(spacing: 10) {
                Button(action: onAim) { Label("Turn to face…", systemImage: "arrow.turn.up.right") }
                    .buttonStyle(HairlineButtonStyle())
                Button(action: onDuplicate) { Label("Duplicate", systemImage: "plus.square.on.square") }
                    .buttonStyle(HairlineButtonStyle())
                Spacer()
                Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
            }
        }
        .padding()
        .background(Theme.surface)
    }
}

/// The person's settings, shared by the panel and the add flow.
struct CharacterFields: View {
    let character: PrevisCharacter
    let update: (@escaping (inout PrevisCharacter) -> Void) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(CharacterType.allCases) { t in
                    TagChip(text: t.label, selected: character.type == t) {
                        update { c in
                            // Keep a height the user chose; an untouched one follows the type.
                            guard c.type != t else { return }
                            let untouched = abs(c.height - c.type.defaultHeight) < 0.005
                            c.type = t
                            if untouched || !t.heightRange.contains(c.height) { c.height = t.defaultHeight }
                        }
                    }
                }
                Spacer()
                TagChip(text: character.posture == .sitting ? "Sitting" : "Standing", selected: true) {
                    update { $0.posture = $0.posture == .sitting ? .standing : .sitting }
                }
                .accessibilityHint("Switches between standing and sitting")
            }
            HStack(spacing: 14) {
                slider("HEIGHT", value: character.height, range: character.type.heightRange, format: { UnitsFormatter.distance($0) }) { v in
                    update { $0.height = v }
                }
                slider("BUILD", value: character.build, range: 0...1, format: { _ in character.buildLabel }) { v in
                    update { $0.build = v }
                }
            }
            HStack(spacing: 8) {
                Text("SKIN").font(.fsLabel).tracking(Theme.tracking).foregroundStyle(Theme.textTertiary)
                ForEach(SkinTone.allCases) { tone in
                    let c = tone.rgb
                    Button { update { $0.skinTone = tone } } label: {
                        Circle().fill(Color(red: c.r, green: c.g, blue: c.b))
                            .frame(width: 26, height: 26)
                            .overlay(Circle().stroke(character.skinTone == tone ? Color.white : Color.clear, lineWidth: 2).padding(-3))
                            .frame(width: 34, height: 34)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Skin tone: \(tone.label)")
                    .accessibilityAddTraits(character.skinTone == tone ? .isSelected : [])
                }
            }
        }
    }

    private func slider(_ title: String, value: Double, range: ClosedRange<Double>,
                        format: @escaping (Double) -> String, set: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.fsLabel).tracking(Theme.tracking).foregroundStyle(Theme.textTertiary)
                Spacer()
                Text(format(value)).font(.fsMono)
            }
            Slider(value: Binding(get: { min(max(value, range.lowerBound), range.upperBound) }, set: set), in: range)
                .accessibilityLabel(title.capitalized)
                .accessibilityValue(format(value))
        }
    }
}

/// Bottom panel for a placed light meter: the reading, what makes it up, and a target.
struct MeterPanel: View {
    let meter: LightMeter
    let reading: LightingCalculator.Reading
    let exposure: ExposureSettings
    let lightName: (UUID) -> String
    let update: (@escaping (inout LightMeter) -> Void) -> Void
    var onDelete: () -> Void

    var body: some View {
        let stops = exposure.stops(forLux: reading.lux)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                TextField("Name", text: Binding(get: { meter.name }, set: { v in update { $0.name = v } })).font(.fsHeadline)
                Spacer()
                ProvenanceBadge(provenance: .estimated)
            }
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                StatView(label: "Incident", value: LuxFormat.lux(reading.lux))
                StatView(label: "Stop", value: ExposureSettings.stopLabel(exposure.tStop(forLux: reading.lux)))
                StatView(label: "vs \(ExposureSettings.stopLabel(exposure.tStop))", value: ExposureSettings.stopsDelta(stops),
                         highlight: abs(stops) <= 1.0 / 6)
            }
            if !reading.contributions.isEmpty {
                let top = reading.contributions.sorted { $0.lux > $1.lux }.prefix(3)
                Text(top.map { "\(lightName($0.lightID))\($0.viaBounce == nil ? "" : " (bounce)") \(LuxFormat.lux($0.lux))" }.joined(separator: " · "))
                    .font(.fsCaption).foregroundStyle(Theme.textSecondary).lineLimit(2)
            }
            HStack(spacing: 6) {
                ForEach(MeterFacing.allCases) { f in
                    TagChip(text: f.label, selected: meter.facing == f) { update { $0.facing = f } }
                }
            }
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("HEIGHT").font(.fsLabel).tracking(Theme.tracking).foregroundStyle(Theme.textTertiary)
                        Spacer()
                        Text(UnitsFormatter.distance(meter.height)).font(.fsMono)
                    }
                    Slider(value: Binding(get: { meter.height }, set: { v in update { $0.height = v } }), in: 0...3)
                        .accessibilityLabel("Meter height")
                }
                if meter.facing == .bearing {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("FACING").font(.fsLabel).tracking(Theme.tracking).foregroundStyle(Theme.textTertiary)
                            Spacer()
                            Text(String(format: "%.0f°", meter.bearing)).font(.fsMono)
                        }
                        Slider(value: Binding(get: { meter.bearing }, set: { v in update { $0.bearing = v } }), in: 0...360)
                            .accessibilityLabel("Meter direction")
                    }
                }
            }
            HStack {
                Spacer()
                Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
            }
        }
        .padding()
        .background(Theme.surface)
    }
}

/// Bottom panel for a set piece from the scan: hide it, its kind, or just its name.
struct SetPiecePanel: View {
    let object: PlanObject
    let display: SceneDisplay
    let updateDisplay: (@escaping (inout SceneDisplay) -> Void) -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(object.category).font(.fsHeadline)
                Spacer()
                Text("\(UnitsFormatter.distance(object.width)) × \(UnitsFormatter.distance(object.depth)) × \(UnitsFormatter.distance(object.height))")
                    .font(.fsMono).foregroundStyle(Theme.textSecondary)
            }
            Text("Set piece from the scan. Hiding it changes only what you see; the scan is kept.")
                .font(.fsCaption).foregroundStyle(Theme.textTertiary)
            HStack(spacing: 10) {
                Button {
                    updateDisplay { $0.setHidden(item: SceneItemKey.object(object.id), true) }
                    onClose()
                } label: { Label("Hide", systemImage: "eye.slash") }
                    .buttonStyle(HairlineButtonStyle())
                Button {
                    updateDisplay { $0.setHidden(category: object.category, true) }
                    onClose()
                } label: { Label("Hide all \(object.category.lowercased())", systemImage: "eye.slash") }
                    .buttonStyle(HairlineButtonStyle())
                Spacer()
            }
            Toggle("Show set piece names", isOn: Binding(get: { display.showsLabels(.objects) },
                                                         set: { v in updateDisplay { $0.setLabels(.objects, shown: v) } }))
                .font(.fsCaption)
                .tint(Theme.accent)
        }
        .padding()
        .background(Theme.surface)
    }
}

/// Everything that can be shown or hidden, in one list: scan parts, each kind of set piece and
/// each piece, planned items, labels, glass and walls.
struct LayersSheet: View {
    let plan: FloorPlan
    @Binding var display: SceneDisplay
    var hasScan3D: Bool
    var onAlign: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    private var categories: [(String, [PlanObject])] {
        let groups = Dictionary(grouping: plan.objects, by: \.category)
        return groups.keys.sorted().map { ($0, groups[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            Form {
                scanSection
                setPieceSection
                plannedSection
                labelSection
                showAllSection
            }
            .fsScreen()
            .navigationTitle("Show and hide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }


    private var scanSection: some View {
        Section("Scan") {
            ForEach(SceneGroup.allCases.filter(\.isScan)) { g in
                groupToggle(g)
            }
            if !display.isHidden(group: .windows) {
                SliderRow(title: "Window glass in 3D", value: Binding(get: { display.windowOpacityValue }, set: { display.windowOpacity = $0 }),
                          range: 0...1, step: 0.05, format: { $0 < 0.03 ? "Clear" : "\(Int(($0 * 100).rounded())) % opaque" })
            }
            SliderRow(title: "Light through glass", value: Binding(get: { display.windowTransmissionValue }, set: { display.windowTransmission = $0 }),
                      range: 0...1, step: 0.01, format: { "\(Int(($0 * 100).rounded())) %" })
            if !display.isHidden(group: .walls) {
                SliderRow(title: "Walls in 3D", value: Binding(get: { display.wallOpacityValue }, set: { display.wallOpacity = $0 }),
                          range: 0.1...1, step: 0.05, format: { $0 > 0.97 ? "Solid" : "\(Int(($0 * 100).rounded())) %" })
            }
            if let onAlign, hasScan3D {
                Button { dismiss(); onAlign() } label: { Label("Level and align scan…", systemImage: "level") }
            }
        }
    }

    @ViewBuilder
    private var setPieceSection: some View {
        if !categories.isEmpty && !display.isHidden(group: .furniture) {
            Section("Set pieces") {
                ForEach(Array(categories.enumerated()), id: \.offset) { pair in
                    let category = pair.element.0, objects = pair.element.1
                    Toggle(isOn: Binding(get: { !display.isHidden(category: category) },
                                         set: { display.setHidden(category: category, !$0) })) {
                        Text("\(category) (\(objects.count))")
                    }
                    if objects.count > 1 && !display.isHidden(category: category) {
                        ForEach(Array(objects.enumerated()), id: \.element.id) { pair in
                            let i = pair.offset, o = pair.element
                            Toggle(isOn: Binding(get: { !display.isHidden(item: SceneItemKey.object(o.id)) },
                                                 set: { display.setHidden(item: SceneItemKey.object(o.id), !$0) })) {
                                Text("\(category) \(i + 1) · \(UnitsFormatter.distance(o.width)) × \(UnitsFormatter.distance(o.depth))")
                                    .font(.fsCaption).foregroundStyle(Theme.textSecondary)
                            }
                            .padding(.leading, 16)
                        }
                    } else if let o = objects.first, objects.count == 1, display.isHidden(item: SceneItemKey.object(o.id)) {
                        Button("Show hidden \(category.lowercased())") { display.setHidden(item: SceneItemKey.object(o.id), false) }
                    }
                }
            }
        }
    }

    private var plannedSection: some View {
        Section("Planned") {
            ForEach(SceneGroup.allCases.filter { !$0.isScan }) { g in groupToggle(g) }
            Toggle("Exposure map on plan", isOn: Binding(get: { display.luxMapOn }, set: { display.showLuxMap = $0 ? true : nil }))
        }
    }

    private var labelSection: some View {
        Section("Labels") {
            ForEach(SceneLabelGroup.allCases) { l in
                Toggle(l.label, isOn: Binding(get: { display.showsLabels(l) }, set: { display.setLabels(l, shown: $0) }))
            }
        }
    }

    @ViewBuilder
    private var showAllSection: some View {
        if display.hiddenCount > 0 {
            Section {
                Button("Show everything") { display.showAll() }
            }
        }
    }

    private func groupToggle(_ g: SceneGroup) -> some View {
        Toggle(isOn: Binding(get: { !display.isHidden(group: g) }, set: { display.setHidden(group: g, !$0) })) {
            Label(g.label, systemImage: g.symbol)
        }
    }
}

/// Camera settings that turn lux into stops.
struct ExposureSheet: View {
    @Binding var exposure: ExposureSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                summarySection
                sensitivitySection
                shutterSection
                lensSection
            }
            .fsScreen()
            .navigationTitle("Camera exposure")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private var summarySection: some View {
        let key = LuxFormat.lux(exposure.keyLux)
        let lens = "\(ExposureSettings.stopLabel(exposure.tStop)) ≈ \(ExposureSettings.stopLabel(exposure.fStop, prefix: "f/"))"
        return Section {
            HStack {
                StatView(label: "Key level", value: key)
                StatView(label: "Lens", value: lens)
            }
        } footer: {
            Text("An incident reading of \(key) on a subject exposes it correctly at these settings. Each doubling of the light is one stop.")
        }
    }

    private var sensitivitySection: some View {
        Section("Sensitivity") {
            Picker("ISO", selection: $exposure.iso) {
                ForEach(isoOptions, id: \.self) { v in
                    Text("\(Int(v))").tag(v)
                }
            }
        }
    }

    private var isoOptions: [Double] {
        var v = ExposureSettings.isoPresets
        if !v.contains(exposure.iso) { v.append(exposure.iso); v.sort() }
        return v
    }

    private var usesAngle: Binding<Bool> {
        Binding(get: { exposure.shutterSeconds == nil },
                set: { angle in exposure.shutterSeconds = angle ? nil : exposure.exposureTime })
    }

    private var shutterSpeed: Binding<Double> {
        Binding(get: { exposure.shutterSeconds ?? 1.0 / 50 }, set: { exposure.shutterSeconds = $0 })
    }

    private static let speeds: [Double] = [1.0 / 25, 1.0 / 30, 1.0 / 48, 1.0 / 50, 1.0 / 60, 1.0 / 100, 1.0 / 125, 1.0 / 250, 1.0 / 500]

    private var shutterSection: some View {
        Section("Shutter") {
            Picker("Set shutter as", selection: usesAngle) {
                Text("Angle").tag(true)
                Text("Speed").tag(false)
            }
            .pickerStyle(.segmented)
            if exposure.shutterSeconds == nil {
                Picker("Frame rate", selection: $exposure.frameRate) {
                    ForEach(ExposureSettings.frameRates, id: \.self) { v in
                        Text(String(format: "%g", v)).tag(v)
                    }
                }
                Picker("Shutter angle", selection: $exposure.shutterAngle) {
                    ForEach(ExposureSettings.shutterAngles, id: \.self) { v in
                        Text(ExposureSettings.trim(v) + "°").tag(v)
                    }
                }
            } else {
                Picker("Shutter speed", selection: shutterSpeed) {
                    ForEach(Self.speeds, id: \.self) { v in
                        Text(ExposureSettings.speedLabel(v)).tag(v)
                    }
                }
            }
            LabeledContent("Exposure time", value: ExposureSettings.speedLabel(exposure.exposureTime))
        }
    }

    private func transmissionLabel(_ t: Double) -> String {
        let f = exposure.tStop * t.squareRoot()
        return "\(Int((t * 100).rounded())) % (f/" + String(format: "%.2g", f) + ")"
    }

    private func ndLabel(_ s: Double) -> String {
        if s == 0 { return "None" }
        let stops = Int(s)
        return "ND " + String(format: "%.1f", s * 0.3) + " (\(stops) stop" + (stops == 1 ? ")" : "s)")
    }

    private var lensSection: some View {
        Section {
            Picker("T-stop", selection: $exposure.tStop) {
                ForEach(stops, id: \.self) { v in
                    Text(ExposureSettings.stopLabel(v)).tag(v)
                }
            }
            SliderRow(title: "Lens transmission", value: $exposure.lensTransmission, range: 0.5...1, step: 0.01,
                      format: transmissionLabel)
            Picker("ND", selection: $exposure.ndStops) {
                ForEach([0.0, 1, 2, 3, 4, 5, 6], id: \.self) { s in
                    Text(ndLabel(s)).tag(s)
                }
            }
        } header: {
            Text("Lens")
        } footer: {
            Text("Exposure is set in T-stops: they include the light the lens loses. The f-stop is the aperture's geometry (T × √transmission) and is shown for reference. A T-stop is a camera setting, not a measure of how bright the scene is.")
        }
    }

    /// Thirds of a stop from T1 to T22, plus the current value.
    private var stops: [Double] {
        var v = (0...27).map { pow(2, Double($0) / 6) }
        if !v.contains(where: { abs($0 - exposure.tStop) < 0.01 }) { v.append(exposure.tStop); v.sort() }
        return v
    }
}

/// Level and place the scan in 3D. Non-destructive: stored as a correction next to the scan.
struct AlignmentSheet: View {
    @ObservedObject var model: VirtualSceneModel
    @Binding var alignment: ScanAlignment
    @Environment(\.dismiss) private var dismiss
    @State private var autoMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SceneKitContainer(model: model, orbit: true)
                    .frame(height: 260)
                    .overlay(alignment: .topLeading) {
                        Text("The grid is the ground plane. Line the floor up with it.")
                            .font(.fsMicro).foregroundStyle(.white.opacity(0.8)).padding(8)
                    }
                Form {
                    Section {
                        Button { level() } label: { Label("Level from the floor", systemImage: "level") }
                        if let autoMessage { Text(autoMessage).font(.fsCaption).foregroundStyle(Theme.textSecondary) }
                    } footer: {
                        Text("Uses the scanned floor to set tilt and height. Fine-tune below.")
                    }
                    Section("Level") {
                        SliderRow(title: "Tilt forward / back", value: $alignment.pitch, range: -15...15, step: 0.1, format: { String(format: "%+.1f°", $0) })
                        SliderRow(title: "Tilt left / right", value: $alignment.roll, range: -15...15, step: 0.1, format: { String(format: "%+.1f°", $0) })
                    }
                    Section("Turn and move") {
                        SliderRow(title: "Turn", value: $alignment.yaw, range: -180...180, step: 0.5, format: { String(format: "%+.1f°", $0) })
                        SliderRow(title: "Floor height", value: $alignment.offsetY, range: -2...2, step: 0.01, format: { String(format: "%+.2f m", $0) })
                        SliderRow(title: "Move left / right", value: $alignment.offsetX, range: -5...5, step: 0.05, format: { String(format: "%+.2f m", $0) })
                        SliderRow(title: "Move forward / back", value: $alignment.offsetZ, range: -5...5, step: 0.05, format: { String(format: "%+.2f m", $0) })
                    }
                    Section {
                        Button("Reset", role: .destructive) { alignment = .identity }
                    } footer: {
                        Text("The scan files aren't changed. Cameras, lights and people move with the scan, so they stay where they are in the room; the plan keeps the scan's own orientation.")
                    }
                }
            }
            .fsScreen()
            .navigationTitle("Level and align")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onChange(of: alignment) { _, a in model.applyAlignment(a) }
        }
    }

    private func level() {
        guard let a = model.autoLevel() else {
            autoMessage = "No floor found in this scan to level from."
            return
        }
        alignment = a
        autoMessage = String(format: "Levelled by %.1f° and %.1f°; floor moved %+.2f m.", a.pitch, a.roll, a.offsetY)
    }
}
