import SwiftUI

/// "My presets": the user's own lighting presets, kept on this phone. The same JSON as the web and
/// desktop planner (`framescan.presets`), so a preset can be copied from one and pasted into the other.
final class LightingPresetLibrary: ObservableObject {
    static let shared = LightingPresetLibrary()
    private static let key = "framescan.presets"

    @Published private(set) var presets: [LightingPreset]

    private init() {
        presets = LightingPreset.decode(UserDefaults.standard.string(forKey: Self.key) ?? "") ?? []
    }

    func save(_ next: [LightingPreset]) {
        presets = next
        UserDefaults.standard.set(LightingPreset.encode(next), forKey: Self.key)
    }
    func add(_ p: LightingPreset) { save(presets + [p]) }
    func update(_ p: LightingPreset) { save(presets.map { $0.id == p.id ? p : $0 }) }
    func remove(_ id: UUID) { save(presets.filter { $0.id != id }) }

    /// Adds pasted presets (one with the same id replaces the old one). Returns how many came in.
    func paste(_ text: String) -> Int? {
        guard let got = LightingPreset.decode(text), !got.isEmpty else { return nil }
        save(presets.filter { p in !got.contains { $0.id == p.id } } + got)
        return got.count
    }
}

/// Save the lights round a person as a preset, kept relative to them or to the nearest window.
struct SavePresetSheet: View {
    let person: PrevisCharacter
    let lights: [LightFixture]
    let camera: PlanPoint?
    let exposure: ExposureSettings
    let plan: FloorPlan?
    let windowTransmission: Double
    var onSaved: (LightingPreset) -> Void

    @ObservedObject private var library = LightingPresetLibrary.shared
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var anchor: LightingPreset.Anchor = .person
    @State private var keepSides = false
    @State private var picked: Set<UUID> = []

    private var window: PlanSegment? { plan.flatMap { LightingPreset.nearestWindow(to: person.position, in: $0) } }

    private func nearby(_ a: LightingPreset.Anchor) -> Set<UUID> {
        let centre = a == .window ? (window?.midpoint ?? person.position) : person.position
        return Set(lights.filter { $0.position.distance(to: centre) <= 4 }.map(\.id))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Preset name", text: $name)
                    Picker("Keep the units relative to", selection: $anchor) {
                        Text("\(person.name) and camera").tag(LightingPreset.Anchor.person)
                        if window != nil { Text("Nearest window").tag(LightingPreset.Anchor.window) }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(anchor == .person
                         ? "Used again, the units go round the person you pick, turned to their camera, and are levelled for the stop."
                         : "Used again, the units go to the same place at a window, at the same dimmer levels. Good for a sun through the glass.")
                }
                Section("Units to keep") {
                    if lights.isEmpty { Text("Place some lights first.").foregroundStyle(Theme.textSecondary) }
                    ForEach(lights) { light in
                        Toggle(isOn: Binding(get: { picked.contains(light.id) },
                                             set: { on in if on { picked.insert(light.id) } else { picked.remove(light.id) } })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(light.name)
                                Text(light.kind.emits ? light.profile.name : light.kind.label)
                                    .font(.fsCaption).foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                }
                if anchor == .person {
                    Section {
                        Toggle("Always keep the key on this side", isOn: $keepSides)
                    } footer: {
                        Text("Off: the key goes on whichever side has more room, like the built-in setups.")
                    }
                }
            }
            .fsScreen()
            .navigationTitle("Save as my preset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(picked.isEmpty) }
            }
            .onAppear {
                if name.isEmpty { name = "My setup \(library.presets.count + 1)" }
                picked = nearby(.person)
            }
            .onChange(of: anchor) { _, a in picked = nearby(a) }
        }
        .presentationDetents([.large])
    }

    private func save() {
        let chosen = lights.filter { picked.contains($0.id) }
        guard !chosen.isEmpty else { return }
        let title = name.trimmingCharacters(in: .whitespaces).isEmpty ? "My setup" : name
        var preset: LightingPreset
        if anchor == .window, let window, let plan {
            preset = LightingPreset.capture(name: title, lights: chosen, window: window, plan: plan)
        } else {
            preset = LightingPreset.capture(name: title, lights: chosen, person: person, camera: camera, exposure: exposure,
                                            plan: plan, windowTransmission: windowTransmission)
            preset.keepSides = keepSides
        }
        library.add(preset)
        onSaved(preset)
        dismiss()
    }
}

/// Rename, tune, delete, copy and paste your presets.
struct ManagePresetsSheet: View {
    @ObservedObject private var library = LightingPresetLibrary.shared
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                if library.presets.isEmpty {
                    Text("No presets yet. Light a person the way you like, then choose “Save as my preset” in their Light menu.")
                        .foregroundStyle(Theme.textSecondary)
                }
                ForEach(library.presets) { preset in
                    NavigationLink {
                        PresetEditor(preset: preset)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.name)
                            Text("\(preset.anchor.label) · \(preset.summary)").font(.fsCaption).foregroundStyle(Theme.textSecondary).lineLimit(2)
                        }
                    }
                }
                .onDelete { idx in for i in idx { library.remove(library.presets[i].id) } }
                Section {
                    Button("Copy all") {
                        UIPasteboard.general.string = LightingPreset.encode(library.presets)
                        message = "Copied. Paste them in the planner on a computer."
                    }
                    .disabled(library.presets.isEmpty)
                    Button("Paste") {
                        if let n = library.paste(UIPasteboard.general.string ?? "") { message = "Added \(n) preset\(n == 1 ? "" : "s")." }
                        else { message = "The clipboard has no FrameScan preset." }
                    }
                } footer: {
                    Text(message ?? "Presets live on this phone. Copy them to use the same ones in the planner.")
                }
            }
            .fsScreen()
            .navigationTitle("My presets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

/// One preset's units: where each goes and how bright it is.
private struct PresetEditor: View {
    @ObservedObject private var library = LightingPresetLibrary.shared
    @State var preset: LightingPreset

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $preset.name)
                if preset.anchor == .person { Toggle("Always keep the key on the saved side", isOn: $preset.keepSides) }
            } footer: {
                Text(preset.anchor == .person ? "Levels are set again for the stop each time you use it." : "Placed at the nearest window, at these dimmer levels.")
            }
            ForEach($preset.units, id: \.light.id) { $unit in
                Section {
                    TextField("Unit name", text: $unit.light.name)
                    if preset.anchor == .person {
                        Stepper("Angle from camera \(Int(unit.angle.rounded()))°", value: $unit.angle, in: -180...180, step: 5)
                        Stepper("Distance \(String(format: "%.1f", unit.distance)) m", value: $unit.distance, in: 0.3...15, step: 0.1)
                        Stepper("Above eyes \(String(format: "%.1f", unit.rise)) m", value: $unit.rise, in: -1.5...4, step: 0.1)
                        if unit.light.kind.emits {
                            if let stops = unit.stopsUnderKey {
                                Stepper(stops >= 0 ? "\(String(format: "%.1f", stops)) stops under key" : "\(String(format: "%.1f", -stops)) stops over key",
                                        value: Binding(get: { stops }, set: { unit.stopsUnderKey = $0 }), in: -3...6, step: 0.5)
                            } else {
                                Text("Keeps its dimmer (\(Int((unit.light.dimmer * 100).rounded())) %)").foregroundStyle(Theme.textSecondary)
                            }
                        }
                    } else {
                        Stepper("Along the window \(String(format: "%.1f", unit.along)) m", value: $unit.along, in: -10...10, step: 0.1)
                        Stepper("Out from the glass \(String(format: "%.1f", unit.out)) m", value: $unit.out, in: -10...20, step: 0.1)
                        Stepper("Height \(String(format: "%.1f", unit.height)) m", value: $unit.height, in: 0...12, step: 0.1)
                        if unit.light.kind.emits {
                            Stepper("Dimmer \(Int((unit.light.dimmer * 100).rounded())) %", value: $unit.light.dimmer, in: 0...1, step: 0.05)
                        }
                    }
                    Button("Remove this unit", role: .destructive) {
                        let id = unit.light.id
                        DispatchQueue.main.async { preset.units.removeAll { $0.light.id == id } }
                    }
                } header: {
                    Text(unit.light.kind.emits ? unit.light.profile.name : unit.light.kind.label)
                }
            }
        }
        .fsScreen()
        .navigationTitle(preset.name)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: preset) { _, p in library.update(p) }
    }
}
