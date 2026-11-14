import SwiftUI

/// Lens set menu plus a horizontal strip of focal-length chips (the set's lenses, or common focal
/// lengths for "any lens") and a custom value. Big targets for set use. The set is remembered on
/// this phone only; the camera itself stores just the focal length, so nothing new syncs.
struct LensPicker: View {
    @Binding var focalLength: Double
    /// When given, a set made for a smaller format says so (estimate).
    var sensor: SensorFormat? = nil
    var aspect: FrameAspect = .sensor
    @AppStorage("plan.lensSetID") private var lensID = LensLibrary.anyID
    @State private var showCustom = false
    @State private var customText = ""

    private var lens: LensSeries? { LensLibrary.planSeries.first { $0.id == lensID } }
    private var steps: [Double] { lens?.steps ?? LensLibrary.commonFocalLengths }
    /// Primes in a set only come in their sizes; zooms and "any lens" take a typed focal length.
    private var allowsCustom: Bool { lens == nil || lens?.isZoom == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Menu {
                Picker("Lens set", selection: Binding(get: { lens?.id ?? LensLibrary.anyID }, set: choose)) {
                    Text("Any lens").tag(LensLibrary.anyID)
                    ForEach(LensLibrary.planSeries) { s in
                        Text("\(s.displayName) · \(s.rangeLabel)").tag(s.id)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(lens?.displayName ?? "Any lens").font(.fsLabel)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                }
                .foregroundStyle(Theme.accent)
                .frame(minHeight: 32)
            }
            .accessibilityLabel("Lens set: \(lens?.displayName ?? "any lens")")
            strip
            if let lens, let sensor, lens.mayVignette(on: sensor, aspect: aspect) {
                Text("\(lens.coverage.label) lenses on this camera: dark corners likely (estimate)")
                    .font(.fsCaption).foregroundStyle(Theme.textSecondary)
            }
        }
        .alert(lens.map { "Focal length (\($0.rangeLabel))" } ?? "Custom focal length (mm)", isPresented: $showCustom) {
            TextField("mm", text: $customText).keyboardType(.decimalPad)
            Button("Set") {
                if let v = Double(customText.replacingOccurrences(of: ",", with: ".")), v > 1, v < 2000 {
                    focalLength = lens?.nearest(to: v) ?? v
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func choose(_ id: String) {
        lensID = id
        focalLength = LensLibrary.fit(lensID: id, focalLength: focalLength, squeeze: 1).focalLength
    }

    private var strip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(steps, id: \.self) { f in
                        let selected = abs(f - focalLength) < 0.01
                        Button { focalLength = f } label: {
                            Text(LensLibrary.focalNumber(f))
                                .font(.system(size: 16, weight: selected ? .regular : .light, design: .monospaced))
                                .frame(minWidth: 44, minHeight: 40)
                                .foregroundStyle(selected ? Theme.onAccent : Theme.textPrimary)
                                .background(selected ? Theme.accent : Theme.surfaceRaised,
                                            in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .id(f)
                    }
                    if allowsCustom {
                        let isCustom = !steps.contains { abs($0 - focalLength) < 0.01 }
                        Button {
                            customText = String(format: "%g", focalLength)
                            showCustom = true
                        } label: {
                            Text(isCustom ? Optics.formatFocal(focalLength) : "Custom")
                                .font(.fsLabel).tracking(Theme.tracking)
                                .padding(.horizontal, 10)
                                .frame(minHeight: 40)
                                .foregroundStyle(isCustom ? Theme.onAccent : Theme.textPrimary)
                                .background(isCustom ? Theme.accent : Theme.surfaceRaised,
                                            in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .onAppear { proxy.scrollTo(focalLength, anchor: .center) }
            .onChange(of: lensID) { _, _ in proxy.scrollTo(focalLength, anchor: .center) }
        }
    }
}

struct SensorPicker: View {
    @Binding var sensorID: String
    @Binding var customSensor: SensorFormat?

    var body: some View {
        Menu {
            ForEach(SensorLibrary.manufacturers, id: \.self) { maker in
                Section(maker.isEmpty ? "Generic" : maker) {
                    ForEach(SensorLibrary.presets.filter { $0.manufacturer == maker }) { s in
                        Button {
                            sensorID = s.id
                        } label: {
                            if s.id == sensorID { Label(s.name, systemImage: "checkmark") } else { Text(s.name) }
                        }
                    }
                }
            }
            Section("User defined") {
                Button("Custom sensor size…") {
                    if customSensor == nil {
                        customSensor = SensorFormat(id: SensorLibrary.customID, manufacturer: "", name: "Custom", width: 36, height: 24)
                    }
                    sensorID = SensorLibrary.customID
                }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(SensorLibrary.format(id: sensorID, custom: customSensor).displayName)
                        .font(.fsBodyStrong)
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text(SensorLibrary.format(id: sensorID, custom: customSensor).sizeDescription)
                        .font(.fsCaption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down").foregroundStyle(Theme.textTertiary)
            }
            .padding(10)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        }
    }
}

struct CustomSensorFields: View {
    @Binding var sensor: SensorFormat?

    var body: some View {
        if let current = sensor {
            HStack {
                LabeledNumberField(title: "Width mm", value: Binding(
                    get: { current.width }, set: { sensor?.width = max(1, $0) }))
                LabeledNumberField(title: "Height mm", value: Binding(
                    get: { current.height }, set: { sensor?.height = max(1, $0) }))
            }
        }
    }
}

struct LabeledNumberField: View {
    var title: String
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.fsLabel).tracking(Theme.tracking).foregroundStyle(Theme.textTertiary)
            TextField(title, value: $value, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .font(.fsValue)
        }
    }
}

enum HeightPreset: CaseIterable, Identifiable {
    case hiHat, low, seated, shoulder, eye, high

    var id: Self { self }
    var label: String {
        switch self {
        case .hiHat: return "Hi-hat"
        case .low: return "Low"
        case .seated: return "Seated"
        case .shoulder: return "Shoulder"
        case .eye: return "Eye"
        case .high: return "High"
        }
    }
    var metres: Double {
        switch self {
        case .hiHat: return 0.3
        case .low: return 0.7
        case .seated: return 1.2
        case .shoulder: return 1.5
        case .eye: return 1.65
        case .high: return 2.3
        }
    }
}

/// Full editor for a camera setup, used for camera positions and shots.
struct CameraRigForm: View {
    @Binding var rig: CameraRig
    var subjectDistance: Double? = nil
    var clearances: PlanGeometry.Clearances? = nil
    var ceilingHeight: Double? = nil

    var body: some View {
        Section("Lens") {
            LensPicker(focalLength: $rig.focalLength, sensor: rig.sensor, aspect: rig.aspect)
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            SensorPicker(sensorID: $rig.sensorID, customSensor: $rig.customSensor)
            if rig.sensorID == SensorLibrary.customID {
                CustomSensorFields(sensor: $rig.customSensor)
            } else {
                QuirkList(quirks: KnownQuirks.sensor(rig.sensorID))
            }
            Picker("Frame lines", selection: $rig.aspect) {
                ForEach(FrameAspect.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            FOVReadout(rig: rig)
        }

        Section("Placement") {
            SliderRow(title: "Height", value: $rig.height, range: 0.1...(max(4, (ceilingHeight ?? 3) - 0.1)), step: 0.05,
                      format: { UnitsFormatter.distance($0) })
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(HeightPreset.allCases) { p in
                        TagChip(text: p.label, selected: abs(rig.height - p.metres) < 0.02) { rig.height = p.metres }
                    }
                }
            }
            SliderRow(title: "Pan", value: $rig.pan, range: 0...360, step: 1, format: { String(format: "%.0f°", $0) })
            SliderRow(title: "Tilt", value: $rig.tilt, range: -60...60, step: 1, format: { String(format: "%+.0f°", $0) })
            Picker("Support", selection: $rig.support) {
                Text("Automatic · \(CameraSupport.automatic(height: rig.height).label)").tag(CameraSupport?.none)
                ForEach(CameraSupport.allCases) { Text($0.label).tag(CameraSupport?.some($0)) }
            }
            if let w = rig.supportWarning {
                Text(w).font(.fsCaption).foregroundStyle(Theme.textSecondary)
            }
            if let ceilingHeight, rig.height > ceilingHeight - 0.25 {
                Label("Less than 25 cm to the ceiling", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.accent)
            }
        }

        if let clearances {
            Section("Space around camera") {
                ClearanceGrid(clearances: clearances)
            }
        }

        Section("Lens calculator") {
            LensCalculator(rig: rig, subjectDistance: subjectDistance)
        }
    }
}

struct SliderRow: View {
    var title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var format: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.fsLabel).tracking(Theme.tracking).foregroundStyle(Theme.textTertiary)
                Spacer()
                Text(format(value)).font(.system(.body, design: .rounded).monospacedDigit().weight(.semibold))
            }
            Slider(value: Binding(get: { min(max(value, range.lowerBound), range.upperBound) }, set: { value = $0 }),
                   in: range, step: step)
        }
    }
}

struct FOVReadout: View {
    var rig: CameraRig

    var body: some View {
        HStack {
            StatView(label: "H-FOV", value: Optics.formatAngle(rig.horizontalFOV))
            StatView(label: "V-FOV", value: Optics.formatAngle(rig.verticalFOV))
            StatView(label: "FF equiv", value: Optics.formatFocal(Optics.fullFrameEquivalent(focalLength: rig.focalLength, sensor: rig.sensor).rounded()))
        }
    }
}

struct ClearanceGrid: View {
    var clearances: PlanGeometry.Clearances

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow {
                StatView(label: "Behind camera", value: UnitsFormatter.distance(clearances.behind),
                         highlight: (clearances.behind ?? 99) < 1.2)
                StatView(label: "In front", value: UnitsFormatter.distance(clearances.front))
            }
            GridRow {
                StatView(label: "Left", value: UnitsFormatter.distance(clearances.left))
                StatView(label: "Right", value: UnitsFormatter.distance(clearances.right))
            }
        }
        if let behind = clearances.behind, behind < 1.2 {
            Text("Tight behind camera — limited room for operator, dolly or pull-back.")
                .font(.fsCaption)
                .foregroundStyle(Theme.accent)
        }
    }
}

/// Answers "how wide is the frame at X?" and "how far back for a full shot?".
struct LensCalculator: View {
    var rig: CameraRig
    var subjectDistance: Double?
    @State private var distance: Double = 3

    var body: some View {
        let area = rig.imageArea
        let d = subjectDistance ?? distance
        VStack(alignment: .leading, spacing: 10) {
            if subjectDistance == nil {
                SliderRow(title: "Subject distance", value: $distance, range: 0.3...30, step: 0.1,
                          format: { UnitsFormatter.distance($0) })
            } else {
                StatView(label: "Subject distance", value: UnitsFormatter.distance(d), highlight: true)
            }
            HStack {
                StatView(label: "Frame width", value: UnitsFormatter.distance(Optics.frameSize(atDistance: d, size: area.width, focalLength: rig.focalLength)))
                StatView(label: "Frame height", value: UnitsFormatter.distance(Optics.frameSize(atDistance: d, size: area.height, focalLength: rig.focalLength)))
            }
            Divider()
            Text("DISTANCE NEEDED ON \(Optics.formatFocal(rig.focalLength))")
                .font(.fsLabel).foregroundStyle(Theme.textSecondary)
            ForEach(Optics.ShotSize.allCases) { size in
                HStack {
                    Text(size.label).font(.fsBody)
                    Spacer()
                    Text(UnitsFormatter.distance(Optics.distance(toCover: size.verticalCoverage, size: area.height, focalLength: rig.focalLength)))
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                }
            }
        }
    }
}
