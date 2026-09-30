import SwiftUI

struct MeasurementListView: View {
    let ref: LocationRef
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var router: AppRouter
    @State private var showManual = false

    var body: some View {
        let location = store.location(ref)
        let grouped = Dictionary(grouping: location?.measurements ?? [], by: \.kind)
        List {
            Section {
                HStack {
                    Button { router.start(.measure(CaptureTarget(ref))) } label: {
                        Label("AR Measure", systemImage: "arkit")
                    }
                    .disabled(!DeviceCapabilities.supportsWorldTracking)
                    Spacer()
                    Button { router.open(.plan(ref)) } label: { Label("On plan", systemImage: "map") }
                    Spacer()
                    Button { showManual = true } label: { Label("Manual", systemImage: "pencil") }
                }
                .buttonStyle(.borderless)
                if let scan = location?.primaryScan {
                    Button {
                        generateFromScan(scan)
                    } label: {
                        Label("Generate room measurements from scan", systemImage: "wand.and.stars")
                    }
                }
            }
            .listRowBackground(Theme.surface)

            ForEach(MeasurementKind.allCases) { kind in
                if let items = grouped[kind], !items.isEmpty {
                    Section(kind.label) {
                        ForEach(items) { m in
                            MeasurementRow(measurement: m)
                                .swipeActions {
                                    Button(role: .destructive) {
                                        store.updateLocation(ref) { $0.measurements.removeAll { $0.id == m.id } }
                                    } label: { Label("Delete", systemImage: "trash") }
                                }
                        }
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            if location?.measurements.isEmpty ?? true {
                EmptyStateView(systemImage: "ruler", title: "No measurements",
                               message: "Measure in AR, on the scanned plan, or generate them from the scan.")
                    .listRowBackground(Color.clear)
            }
        }
        .fsScreen()
        .navigationTitle("Measurements")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showManual) { ManualMeasurementSheet(ref: ref) }
    }

    /// Automatic room measurements (future: fuller automatic dimensioning).
    private func generateFromScan(_ scan: ScanRecord) {
        let s = scan.stats
        var items: [DistanceMeasurement] = []
        func add(_ kind: MeasurementKind, _ label: String, _ value: Double?, vertical: Double? = nil) {
            guard let value, value > 0 else { return }
            items.append(DistanceMeasurement(kind: kind, label: label, value: value, vertical: vertical,
                                             source: .scanAuto, scanID: scan.id))
        }
        add(.roomDimension, "Room width", s.width)
        add(.roomDimension, "Room length", s.length)
        add(.ceilingHeight, "Ceiling height", s.ceilingHeight, vertical: s.ceilingHeight)
        if let low = s.minCeilingHeight, let high = s.ceilingHeight, high - low > 0.1 {
            add(.ceilingHeight, "Lowest ceiling", low, vertical: low)
        }
        for (i, d) in s.doors.enumerated() {
            add(.door, "Door \(i + 1) width (h \(UnitsFormatter.distance(d.height)))", d.width)
        }
        for (i, w) in s.windows.enumerated() {
            add(.window, "Window \(i + 1) width (h \(UnitsFormatter.distance(w.height)), sill \(UnitsFormatter.distance(w.sillHeight)))", w.width)
        }
        store.updateLocation(ref) { loc in
            loc.measurements.removeAll { $0.source == .scanAuto && $0.scanID == scan.id }
            loc.measurements += items
        }
    }
}

struct MeasurementRow: View {
    let measurement: DistanceMeasurement

    var body: some View {
        HStack {
            Image(systemName: measurement.kind.symbol).foregroundStyle(Theme.accent).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(measurement.label.isEmpty ? measurement.kind.label : measurement.label)
                HStack(spacing: 6) {
                    Text(measurement.source.label.uppercased()).font(.fsLabel).foregroundStyle(Theme.textTertiary)
                    if let h = measurement.horizontal, let v = measurement.vertical, measurement.source == .ar {
                        Text("h \(UnitsFormatter.distance(h)) · v \(UnitsFormatter.distance(v))")
                            .font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                }
                if !measurement.notes.isEmpty {
                    Text(measurement.notes).font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            Text(UnitsFormatter.distance(measurement.value, precise: true))
                .font(.body.monospacedDigit().weight(.semibold))
        }
    }
}

struct ManualMeasurementSheet: View {
    let ref: LocationRef
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    @State private var kind: MeasurementKind = .custom
    @State private var label = ""
    @State private var metres: Double = 1
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $kind) {
                    ForEach(MeasurementKind.allCases) { Text($0.label).tag($0) }
                }
                TextField("Label", text: $label)
                HStack {
                    Text("Metres")
                    TextField("m", value: $metres, format: .number.precision(.fractionLength(0...3)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                TextField("Notes", text: $notes, axis: .vertical)
            }
            .fsScreen()
            .navigationTitle("Manual Measurement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let m = DistanceMeasurement(kind: kind, label: label, value: metres, source: .manual, notes: notes)
                        store.updateLocation(ref) { $0.measurements.append(m) }
                        dismiss()
                    }
                    .disabled(metres <= 0)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
