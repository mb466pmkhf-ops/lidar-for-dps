import SwiftUI

/// Bottom panel for the selected lighting unit on the plan: the settings you change most while
/// building a setup, with the rest in `LightForm`.
struct LightPanel: View {
    let light: LightFixture
    let update: (@escaping (inout LightFixture) -> Void) -> Void
    var onDetails: () -> Void
    var onDuplicate: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(light.name).font(.fsHeadline)
                Text(light.summary).font(.fsCaption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                Spacer()
                if light.kind.emits {
                    Toggle("On", isOn: Binding(get: { light.isOn }, set: { v in update { $0.isOn = v } }))
                        .labelsHidden()
                        .tint(Theme.accent)
                        .accessibilityLabel("Light on")
                }
            }
            if light.kind.emits {
                KelvinChips(kelvin: Binding(get: { light.colorTemperature }, set: { v in update { $0.colorTemperature = v } }))
                HStack(spacing: 14) {
                    compact("DIMMER", value: light.dimmer, range: 0.05...1, format: { "\(Int(($0 * 100).rounded())) %" }) { v in
                        update { $0.dimmer = v }
                    }
                    compact("BEAM", value: light.beamAngle, range: 5...180, format: { String(format: "%.0f°", $0) }) { v in
                        update { $0.beamAngle = v }
                    }
                    compact("HEIGHT", value: light.height, range: 0.2...6, format: { UnitsFormatter.distance($0) }) { v in
                        update { $0.height = v }
                    }
                }
            } else {
                HStack(spacing: 14) {
                    compact("WIDTH", value: light.width, range: 0.2...6, format: { UnitsFormatter.distance($0) }) { v in
                        update { $0.width = v }
                    }
                    compact("HEIGHT", value: light.height, range: 0.2...6, format: { UnitsFormatter.distance($0) }) { v in
                        update { $0.height = v }
                    }
                }
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

/// Common colour temperatures as chips, tinted with the colour they make.
struct KelvinChips: View {
    @Binding var kelvin: Double

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Kelvin.presets, id: \.self) { k in
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

/// Everything about one unit, for the Details sheet.
struct LightForm: View {
    @Binding var light: LightFixture

    var body: some View {
        Section("Unit") {
            TextField("Name (e.g. Key, L1)", text: $light.name)
            Picker("Type", selection: $light.kind) {
                ForEach(LightKind.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
            }
            Picker("Role", selection: $light.role) {
                Text("None").tag(LightRole?.none)
                ForEach(LightRole.allCases) { Text($0.label).tag(LightRole?.some($0)) }
            }
            if light.kind.emits {
                TextField("Power (e.g. 1.2K, 600 W)", text: $light.power)
                TextField("Modifier (e.g. Chimera, 40° grid)", text: $light.modifier)
            }
        }
        if light.kind.emits {
            Section("Output") {
                Toggle("On", isOn: $light.isOn)
                SliderRow(title: "Colour temperature", value: $light.colorTemperature, range: 2000...10000, step: 50,
                          format: { "\(Int($0)) K" })
                KelvinChips(kelvin: $light.colorTemperature)
                TextField("Gel (e.g. ¼ CTO, +⅛ green)", text: $light.gel)
                SliderRow(title: "Dimmer", value: $light.dimmer, range: 0.05...1, step: 0.05,
                          format: { "\(Int(($0 * 100).rounded())) %" })
                SliderRow(title: "Beam angle", value: $light.beamAngle, range: 5...180, step: 1,
                          format: { String(format: "%.0f°", $0) })
            }
        }
        Section("Placement") {
            SliderRow(title: "Height", value: $light.height, range: 0.2...6, step: 0.05, format: { UnitsFormatter.distance($0) })
            SliderRow(title: "Pan", value: $light.pan, range: 0...360, step: 1, format: { String(format: "%.0f°", $0) })
            SliderRow(title: "Tilt", value: $light.tilt, range: -90...45, step: 1, format: { String(format: "%+.0f°", $0) })
            SliderRow(title: "Width", value: $light.width, range: 0.1...6, step: 0.05, format: { UnitsFormatter.distance($0) })
        }
        Section("Notes") {
            TextField("Notes", text: $light.notes, axis: .vertical)
        }
    }
}
