import SwiftUI

/// What the light controls need to show readings and solve targets: the camera's exposure and
/// the meter positions (placed meters and people's faces).
struct LightingContext {
    var exposure = ExposureSettings()
    var meters: [MeterPoint] = []
    /// Total reading at a meter with the current setup.
    var reading: (MeterPoint) -> LightingCalculator.Reading = { _ in .zero }
    /// Output for a unit so the meter reaches `lux`.
    var solve: (LightFixture, MeterPoint, Double) -> LightingCalculator.IntensitySolution = { _, _, _ in .noContribution }

    /// The meter a unit matters most to: where it contributes the most light.
    func primaryMeter(for light: LightFixture) -> (meter: MeterPoint, own: Double, total: Double)? {
        var best: (MeterPoint, Double, Double)?
        for m in meters {
            let r = reading(m)
            let own = r.contributions.filter { $0.lightID == light.id }.reduce(0) { $0 + $1.lux }
            if own > (best?.1 ?? 0) { best = (m, own, r.lux) }
        }
        return best.map { (meter: $0.0, own: $0.1, total: $0.2) }
    }

    /// Plain-language result of a target solve.
    static func describe(_ s: LightingCalculator.IntensitySolution, target: Double) -> String {
        switch s {
        case .output(let o):
            return "Set to \(Int((o * 100).rounded())) % for \(LuxFormat.lux(target))."
        case .tooDim(let maxLux, let d):
            let move = d.map { " Move it to about \(UnitsFormatter.distance($0)) away, or use a brighter unit." } ?? ""
            return "Even at full it gives \(LuxFormat.lux(maxLux)) here.\(move)"
        case .othersTooBright(let others):
            return "The other units already give \(LuxFormat.lux(others)) here. Turn them down first."
        case .noContribution:
            return "This unit doesn't reach that point (aimed away, cut, blocked or off)."
        }
    }
}

enum LuxFormat {
    static func lux(_ v: Double) -> String {
        if v >= 10_000 { return String(format: "%.0fk lx", v / 1000) }
        if v >= 1000 { return String(format: "%.1fk lx", v / 1000) }
        if v >= 10 { return "\(Int(v.rounded())) lx" }
        return String(format: "%.1f lx", v)
    }

    static func watts(_ w: Double) -> String {
        w >= 1000 ? String(format: "%.2f kW", w / 1000) : "\(Int(w.rounded())) W"
    }
}

/// Bottom panel for the selected lighting unit: the controls used most while building a setup.
/// Everything else is in Details.
struct LightPanel: View {
    let light: LightFixture
    var context = LightingContext()
    let update: (@escaping (inout LightFixture) -> Void) -> Void
    var onDetails: () -> Void
    var onDuplicate: () -> Void
    var onDelete: () -> Void
    @State private var message: String?

    var body: some View {
        let pm = light.photometrics
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(light.name).font(.fsHeadline)
                    Text(light.kind.emits ? pm.profile.name + (pm.modifier.map { " · \($0.name)" } ?? "") : light.kind.label)
                        .font(.fsCaption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
                Spacer()
                if light.kind.emits {
                    Toggle("On", isOn: Binding(get: { light.isOn }, set: { v in update { $0.isOn = v } }))
                        .labelsHidden()
                        .tint(Theme.accent)
                        .accessibilityLabel("Light on")
                }
            }
            if light.kind.emits {
                HStack(alignment: .bottom, spacing: 14) {
                    compact("OUTPUT", value: light.dimmer, range: pm.profile.minOutput...1, format: { "\(Int(($0 * 100).rounded())) %" }) { v in
                        update { $0.dimmer = v }
                    }
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("DRAW").font(.fsLabel).tracking(Theme.tracking).foregroundStyle(Theme.textTertiary)
                        Text("≈ " + LuxFormat.watts(pm.drawWatts)).font(.fsMono)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Estimated power draw \(LuxFormat.watts(pm.drawWatts))")
                }
                ColourControls(light: light, update: update)
                HStack(spacing: 14) {
                    if pm.beamIsAdjustable, let range = pm.beamRange {
                        compact("BEAM", value: light.beamAngle, range: range, format: { String(format: "%.0f°", $0) }) { v in
                            update { $0.beamAngle = v }
                        }
                    }
                    compact("HEIGHT", value: light.height, range: 0.2...6, format: { UnitsFormatter.distance($0) }) { v in
                        update { $0.height = v }
                    }
                    compact("TILT", value: light.tilt, range: -90...45, format: { String(format: "%+.0f°", $0) }) { v in
                        update { $0.tilt = v }
                    }
                }
                readout
            } else {
                HStack(spacing: 14) {
                    compact("WIDTH", value: light.width, range: 0.2...6, format: { UnitsFormatter.distance($0) }) { v in
                        update { $0.width = v }
                    }
                    compact("HEIGHT", value: light.height, range: 0.2...6, format: { UnitsFormatter.distance($0) }) { v in
                        update { $0.height = v }
                    }
                }
                if light.kind == .bounce { readout }
            }
            if let message {
                Text(message).font(.fsCaption).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Button(action: onDetails) { Label("Details", systemImage: "slider.horizontal.3") }
                    .buttonStyle(HairlineButtonStyle())
                Button(action: onDuplicate) { Label("Duplicate", systemImage: "plus.square.on.square") }
                    .buttonStyle(HairlineButtonStyle())
                Spacer()
                Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
            }
        }
        .padding()
        .background(Theme.surface)
        .onChange(of: light.id) { _, _ in message = nil }
    }

    /// This unit's share of the reading where it matters most, in lux and stops.
    @ViewBuilder
    private var readout: some View {
        if let p = context.primaryMeter(for: light) {
            let stops = context.exposure.stops(forLux: p.total)
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AT \(p.meter.name.uppercased())").font(.fsLabel).tracking(Theme.tracking).foregroundStyle(Theme.textTertiary).lineLimit(1)
                    Text("≈ \(LuxFormat.lux(p.own)) of \(LuxFormat.lux(p.total)) · \(ExposureSettings.stopsDelta(stops)) at \(ExposureSettings.stopLabel(context.exposure.tStop))")
                        .font(.fsMono).lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 4)
                ProvenanceBadge(provenance: .estimated)
                if light.kind.emits {
                    Button {
                        let target = p.meter.targetLux ?? context.exposure.keyLux
                        let s = context.solve(light, p.meter, target)
                        if case .output(let o) = s { update { $0.dimmer = o } }
                        message = LightingContext.describe(s, target: target)
                    } label: { Label("Set to key", systemImage: "scope") }
                        .buttonStyle(HairlineButtonStyle())
                        .accessibilityHint("Sets the output so \(p.meter.name) reads the key level for the camera's stop")
                }
            }
        } else if !context.meters.isEmpty {
            Text("Doesn't reach any meter or person.").font(.fsCaption).foregroundStyle(Theme.textTertiary)
        }
    }

    private func compact(_ title: String, value: Double, range: ClosedRange<Double>,
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

/// White (colour temperature within the unit's range) or, on RGB units, colour.
struct ColourControls: View {
    let light: LightFixture
    let update: (@escaping (inout LightFixture) -> Void) -> Void

    var body: some View {
        let cap = light.profile.color
        VStack(alignment: .leading, spacing: 6) {
            if cap.rgb {
                HStack(spacing: 6) {
                    TagChip(text: "White", selected: !light.usesRGB) { update { $0.colorMode = .cct } }
                    TagChip(text: "Colour", selected: light.usesRGB) { update { $0.colorMode = .rgb; if $0.hue == nil { $0.hue = 210; $0.saturation = 0.8 } } }
                }
            }
            if light.usesRGB {
                HueSlider(hue: Binding(get: { light.hue ?? 0 }, set: { v in update { $0.hue = v } }))
                HStack {
                    Text("SAT").font(.fsLabel).tracking(Theme.tracking).foregroundStyle(Theme.textTertiary)
                    Slider(value: Binding(get: { light.saturation ?? 1 }, set: { v in update { $0.saturation = v } }), in: 0...1)
                        .accessibilityLabel("Saturation")
                    Text("\(Int(((light.saturation ?? 1) * 100).rounded())) %").font(.fsMono).frame(width: 44, alignment: .trailing)
                }
            } else if cap.isAdjustable {
                KelvinChips(kelvin: Binding(get: { light.colorTemperature }, set: { v in update { $0.colorTemperature = v } }),
                            range: cap.minKelvin...cap.maxKelvin)
            } else {
                Text("\(Int(cap.minKelvin)) K fixed\(light.filterItems.isEmpty ? "" : " · gelled to \(Int(light.photometrics.kelvin.rounded())) K")")
                    .font(.fsCaption).foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

struct HueSlider: View {
    @Binding var hue: Double

    var body: some View {
        VStack(spacing: 2) {
            LinearGradient(colors: stride(from: 0.0, through: 360, by: 30).map { h in
                let c = Photometry.rgb(hue: h, saturation: 1); return Color(red: c.r, green: c.g, blue: c.b)
            }, startPoint: .leading, endPoint: .trailing)
            .frame(height: 6)
            Slider(value: $hue, in: 0...360)
                .accessibilityLabel("Hue")
                .accessibilityValue("\(Int(hue)) degrees")
        }
    }
}

/// Common colour temperatures as chips, tinted with the colour they make. With a range, only the
/// ones the unit can make (plus its two ends).
struct KelvinChips: View {
    @Binding var kelvin: Double
    var range: ClosedRange<Double>? = nil

    private var values: [Double] {
        guard let range else { return Kelvin.presets }
        var v = Kelvin.presets.filter { range.contains($0) }
        if !v.contains(range.lowerBound) { v.insert(range.lowerBound, at: 0) }
        if !v.contains(range.upperBound) { v.append(range.upperBound) }
        return v
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(values, id: \.self) { k in
                    let rgb = Kelvin.rgb(k)
                    let selected = abs(kelvin - k) < 1
                    Button { kelvin = k } label: {
                        HStack(spacing: 5) {
                            Circle().fill(Color(red: rgb.r, green: rgb.g, blue: rgb.b)).frame(width: 9, height: 9)
                            Text("\(Int(k)) K").font(.fsLabel).tracking(Theme.tracking)
                        }
                        .padding(.horizontal, 10)
                        .frame(minHeight: 34)
                        .foregroundStyle(selected ? Theme.textPrimary : Theme.textTertiary)
                        .overlay(Rectangle().stroke(selected ? Color.white.opacity(0.7) : Theme.hairline, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }
}

/// Everything about one unit, for the Details sheet. Simple settings first; photometric data,
/// shaping and targets below.
struct LightForm: View {
    @Binding var light: LightFixture
    var context = LightingContext()
    @State private var distance: Double = 3
    @State private var targetMeter: MeterPoint.Source?
    @State private var targetLux: Double?
    @State private var solveMessage: String?

    var body: some View {
        let pm = light.photometrics
        Section("Unit") {
            TextField("Name (e.g. Key, L1)", text: $light.name)
            if light.kind.emits {
                NavigationLink {
                    FixturePicker(selectedID: light.profile.id) { p in light.apply(profile: p) }
                } label: {
                    LabeledContent("Fixture", value: pm.profile.name)
                }
            } else {
                Picker("Type", selection: $light.kind) {
                    ForEach(LightKind.allCases.filter { !$0.emits }) { Label($0.label, systemImage: $0.symbol).tag($0) }
                }
            }
            Picker("Role", selection: $light.role) {
                Text("None").tag(LightRole?.none)
                ForEach(LightRole.allCases) { Text($0.label).tag(LightRole?.some($0)) }
            }
        }
        if light.kind.emits {
            Section {
                Toggle("On", isOn: $light.isOn)
                SliderRow(title: "Output", value: $light.dimmer, range: pm.profile.minOutput...1, step: 0.01,
                          format: { "\(Int(($0 * 100).rounded())) %" })
                LabeledContent("Power", value: "\(LuxFormat.watts(pm.profile.ratedPower)) rated · ≈ \(LuxFormat.watts(pm.drawWatts)) now")
                if pm.profile.color.isAdjustable && !light.usesRGB {
                    SliderRow(title: "Colour temperature", value: $light.colorTemperature,
                              range: pm.profile.color.minKelvin...pm.profile.color.maxKelvin, step: 50,
                              format: { "\(Int($0)) K" })
                }
                ColourControls(light: light) { mutate in mutate(&light) }
            } header: {
                Text("Output")
            } footer: {
                Text(pm.profile.technology == .tungsten ? "Output is light output. Tungsten draws more than its share when dimmed and warms as it dims."
                     : "Output is light output. Draw is an estimate from the rated power.")
            }
            shapingSection(pm)
            filtersSection
            photometricsSection(pm)
            if !context.meters.isEmpty { targetSection }
        }
        Section("Placement") {
            SliderRow(title: "Height", value: $light.height, range: 0.2...6, step: 0.05, format: { UnitsFormatter.distance($0) })
            SliderRow(title: "Pan", value: $light.pan, range: 0...360, step: 1, format: { String(format: "%.0f°", $0) })
            SliderRow(title: "Tilt", value: $light.tilt, range: -90...45, step: 1, format: { String(format: "%+.0f°", $0) })
            if !light.kind.emits {
                SliderRow(title: "Width", value: $light.width, range: 0.1...6, step: 0.05, format: { UnitsFormatter.distance($0) })
                SliderRow(title: "Frame height", value: Binding(get: { light.boardHeight ?? light.width }, set: { light.boardHeight = $0 }),
                          range: 0.1...6, step: 0.05, format: { UnitsFormatter.distance($0) })
            }
        }
        Section("Notes") {
            TextField("Notes", text: $light.notes, axis: .vertical)
        }
    }

    @ViewBuilder
    private func shapingSection(_ pm: ResolvedPhotometrics) -> some View {
        let options = FixtureLibrary.modifiers(for: pm.profile)
        Section {
            if !options.isEmpty {
                Picker("Modifier", selection: Binding(get: { light.modifierID ?? pm.profile.defaultModifierID ?? "none" },
                                                      set: { light.modifierID = $0 })) {
                    if pm.profile.defaultModifierID == nil { Text("None").tag("none") }
                    ForEach(options) { Text($0.name).tag($0.id) }
                }
            }
            if pm.beamIsAdjustable, let range = pm.beamRange {
                SliderRow(title: "Beam (spot ↔ flood)", value: $light.beamAngle, range: range, step: 1,
                          format: { String(format: "%.0f°", $0) })
            } else {
                LabeledContent("Beam", value: pm.distribution == .beam ? String(format: "%.0f°", pm.beamAngle) : beamShapeLabel(pm.distribution))
            }
            if pm.barnDoorsAvailable {
                Toggle("Barn doors", isOn: Binding(get: { light.barnDoors != nil }, set: { light.barnDoors = $0 ? BarnDoors() : nil }))
                if light.barnDoors != nil {
                    doorSlider("Top", \.top)
                    doorSlider("Bottom", \.bottom)
                    doorSlider("Left", \.left)
                    doorSlider("Right", \.right)
                    Button("Open all doors") { light.barnDoors = BarnDoors() }
                }
            }
        } header: {
            Text("Beam and shaping")
        } footer: {
            Text(pm.barnDoorsAvailable && light.barnDoors != nil
                 ? "Each door is the angle from the beam's centre where it cuts the light; 90° is fully open. Doors are modelled with a soft edge about 6° wide."
                 : "Beam angle is where the light falls to half its centre brightness.")
        }
    }

    private func beamShapeLabel(_ d: BeamDistribution) -> String {
        switch d {
        case .beam: return "Beam"
        case .lambertian: return "Soft, 120° (diffuse)"
        case .omni: return "All round"
        case .tube: return "All round the tube"
        }
    }

    private func doorSlider(_ title: String, _ key: WritableKeyPath<BarnDoors, Double>) -> some View {
        SliderRow(title: title, value: Binding(get: { light.barnDoorSettings[keyPath: key] },
                                               set: { v in var d = light.barnDoorSettings; d[keyPath: key] = v; light.barnDoors = d }),
                  range: 0...90, step: 1, format: { $0 >= 89.5 ? "Open" : String(format: "%.0f°", $0) })
    }

    private var filtersSection: some View {
        Section {
            NavigationLink {
                FilterPicker(selected: Binding(get: { light.filterIDs ?? [] }, set: { light.filterIDs = $0.isEmpty ? nil : $0 }))
            } label: {
                LabeledContent("Gels and diffusion", value: light.filterItems.isEmpty ? "None" : light.filterItems.map(\.name).joined(separator: ", "))
            }
        } footer: {
            if !light.filterItems.isEmpty {
                let t = light.filterItems.reduce(1.0) { $0 * $1.transmission }
                Text("Together they pass \(Int((t * 100).rounded())) % (\(ExposureSettings.stopsDelta(log2(t))) stops).")
            }
        }
    }

    @ViewBuilder
    private func photometricsSection(_ pm: ResolvedPhotometrics) -> some View {
        Section {
            HStack {
                StatView(label: "At \(UnitsFormatter.distance(distance))", value: LuxFormat.lux(pm.illuminanceOnAxis(at: distance)),
                         provenance: pm.provenance)
                StatView(label: "Stop there", value: ExposureSettings.stopLabel(context.exposure.tStop(forLux: pm.illuminanceOnAxis(at: distance))))
            }
            SliderRow(title: "Distance", value: $distance, range: 0.5...15, step: 0.1, format: { UnitsFormatter.distance($0) })
            ForEach([1.0, 2, 3, 5, 8], id: \.self) { d in
                LabeledContent(UnitsFormatter.distance(d), value: LuxFormat.lux(pm.illuminanceOnAxis(at: d)))
                    .font(.fsMono)
            }
            LabeledContent("Peak intensity", value: "≈ \(Int(pm.peakIntensity.rounded())) cd")
            LabeledContent("Flux leaving the unit", value: "≈ \(Int(pm.flux.rounded())) lm")
            Toggle("Use my own photometric data", isOn: Binding(
                get: { light.photometricOverride != nil },
                set: { on in
                    light.photometricOverride = on
                        ? PhotometricReference(lux: pm.profile.reference.lux, distance: pm.profile.reference.distance,
                                               beamAngle: pm.profile.reference.beamAngle, provenance: .manual, note: "From the maker's data")
                        : nil
                }))
            if let ref = light.photometricOverride {
                HStack {
                    Text("Lux")
                    TextField("Lux", value: Binding(get: { ref.lux }, set: { v in light.photometricOverride?.lux = max(v, 0.1) }), format: .number)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("At distance (m)")
                    TextField("m", value: Binding(get: { ref.distance }, set: { v in light.photometricOverride?.distance = max(v, 0.1) }), format: .number)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
                if pm.beamRange != nil {
                    HStack {
                        Text("Measured at beam (°)")
                        TextField("°", value: Binding(get: { ref.beamAngle ?? pm.beamAngle }, set: { v in light.photometricOverride?.beamAngle = v }), format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                }
            }
        } header: {
            Text("Throw (on the beam's centre, nothing in the way)")
        } footer: {
            Text((pm.notes + ["Lux is calculated from photometric data, not from how bright the 3D view looks. Room reflections aren't included, so real readings indoors are usually higher."]).joined(separator: " "))
        }
    }

    @ViewBuilder
    private var targetSection: some View {
        let meter = context.meters.first { $0.source == targetMeter } ?? context.meters.first!
        let target = targetLux ?? meter.targetLux ?? context.exposure.keyLux
        Section {
            Picker("Where", selection: Binding(get: { meter.source }, set: { targetMeter = $0; solveMessage = nil })) {
                ForEach(context.meters) { m in Text(m.name).tag(m.source) }
            }
            let now = context.reading(meter).lux
            LabeledContent("Now", value: "≈ \(LuxFormat.lux(now)) · \(ExposureSettings.stopLabel(context.exposure.tStop(forLux: now)))")
            HStack {
                Text("Target lux")
                TextField("lux", value: Binding(get: { target.rounded() }, set: { targetLux = max($0, 0.1) }), format: .number)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
            Button("Key for \(ExposureSettings.stopLabel(context.exposure.tStop)) (\(LuxFormat.lux(context.exposure.keyLux)))") {
                targetLux = context.exposure.keyLux
            }
            Button {
                let s = context.solve(light, meter, target)
                if case .output(let o) = s { light.dimmer = o; light.isOn = true }
                solveMessage = LightingContext.describe(s, target: target)
            } label: { Label("Set output to reach target", systemImage: "scope") }
            if let solveMessage { Text(solveMessage).font(.fsCaption).foregroundStyle(Theme.textSecondary) }
        } header: {
            Text("Target")
        } footer: {
            Text("Keeps the other units as they are and sets this one's output. Readings are estimates.")
        }
    }
}

/// Fixture library grouped by family, with the figures that tell units apart.
struct FixturePicker: View {
    let selectedID: String
    let onPick: (FixtureProfile) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(FixtureCategory.allCases) { cat in
                let items = FixtureLibrary.profiles.filter { $0.category == cat }
                if !items.isEmpty {
                    Section(cat.label) {
                        ForEach(items) { p in
                            Button {
                                onPick(p)
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(p.name).font(.fsBody).foregroundStyle(Theme.textPrimary)
                                        Text(specs(p)).font(.fsMicro).foregroundStyle(Theme.textSecondary)
                                    }
                                    Spacer()
                                    if p.id == selectedID { Image(systemName: "checkmark") }
                                }
                            }
                        }
                    }
                }
            }
            Section {
                Text("Generic fixture types with estimated output. Where you know a unit's real figures, enter them under Throw in the unit's details.")
                    .font(.fsCaption).foregroundStyle(Theme.textSecondary)
            }
        }
        .fsScreen()
        .navigationTitle("Fixture")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func specs(_ p: FixtureProfile) -> String {
        let colour = p.color.rgb ? "RGB + \(Int(p.color.minKelvin))–\(Int(p.color.maxKelvin)) K"
            : (p.color.isAdjustable ? "\(Int(p.color.minKelvin))–\(Int(p.color.maxKelvin)) K" : "\(Int(p.color.minKelvin)) K")
        let beam = p.beamRange.map { "\(Int($0.lowerBound))–\(Int($0.upperBound))°" } ?? (p.distribution == .beam ? "\(Int(p.defaultBeam))°" : "soft")
        return "\(LuxFormat.watts(p.ratedPower)) · \(colour) · \(beam) · ≈ \(LuxFormat.lux(p.reference.lux)) at \(String(format: "%g", p.reference.distance)) m"
    }
}

struct FilterPicker: View {
    @Binding var selected: [String]

    var body: some View {
        List {
            group("Colour correction", FixtureLibrary.filters.filter { $0.mired != 0 || $0.id.contains("green") })
            group("Neutral density", FixtureLibrary.filters.filter { $0.id.hasPrefix("nd") })
            group("Diffusion", FixtureLibrary.filters.filter { $0.diffusion != nil })
        }
        .fsScreen()
        .navigationTitle("Gels and diffusion")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func group(_ title: String, _ items: [LightFilter]) -> some View {
        Section(title) {
            ForEach(items) { f in
                Button {
                    if selected.contains(f.id) { selected.removeAll { $0 == f.id } } else { selected.append(f.id) }
                } label: {
                    HStack {
                        Text(f.name).foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text("\(Int((f.transmission * 100).rounded())) %").font(.fsMono).foregroundStyle(Theme.textSecondary)
                        if selected.contains(f.id) { Image(systemName: "checkmark") }
                    }
                }
            }
        }
    }
}
