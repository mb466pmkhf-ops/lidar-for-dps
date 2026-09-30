import SwiftUI

/// LOCATION A vs LOCATION B (vs C): the numbers a DOP compares when choosing between recces.
struct CompareView: View {
    @EnvironmentObject private var store: ProjectStore
    @State private var selections: [LocationRef?] = [nil, nil]

    private var options: [(project: Project, location: Location)] { store.allLocationRefs }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if options.count < 2 {
                    EmptyStateView(systemImage: "rectangle.split.2x1", title: "Need two locations",
                                   message: "Scan or add at least two locations to compare them.")
                        .card()
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 10) {
                            labelsColumn
                            ForEach(selections.indices, id: \.self) { i in
                                column(index: i)
                            }
                            if selections.count < 3 {
                                Button { selections.append(nil) } label: {
                                    Label("Add", systemImage: "plus").frame(width: 80, height: 60)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .fsScreen()
        .navigationTitle("Compare Locations")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: preselect)
    }

    private func preselect() {
        guard selections.allSatisfy({ $0 == nil }) else { return }
        for (i, pair) in options.prefix(2).enumerated() {
            selections[i] = LocationRef(projectID: pair.project.id, locationID: pair.location.id)
        }
    }

    private static let rowLabels = ["Plan", "Photo", "Room (W × L)", "Floor area", "Ceiling", "Lowest ceiling",
                                    "Windows", "Doors", "Openings", "Furniture", "Camera positions", "Shots",
                                    "Tags", "Notes"]
    private static let rowHeights: [CGFloat] = [140, 100, 44, 44, 44, 44, 44, 44, 44, 44, 44, 44, 70, 120]

    private var labelsColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 56)
            ForEach(Array(Self.rowLabels.enumerated()), id: \.offset) { i, label in
                Text(label.uppercased())
                    .font(.fsLabel)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 96, height: Self.rowHeights[i], alignment: .leading)
            }
        }
    }

    private func column(index: Int) -> some View {
        let ref = selections[index]
        let location = ref.flatMap { store.location($0) }
        let stats = location?.primaryScan?.stats
        let letter = String(Character(UnicodeScalar(65 + index)!))
        return VStack(alignment: .leading, spacing: 0) {
            Menu {
                ForEach(options, id: \.location.id) { pair in
                    Button("\(pair.location.name) — \(pair.project.name)") {
                        selections[index] = LocationRef(projectID: pair.project.id, locationID: pair.location.id)
                    }
                }
                if selections.count > 2 {
                    Button("Remove column", role: .destructive) { selections.remove(at: index) }
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("LOCATION \(letter)").font(.fsLabel).foregroundStyle(Theme.accent)
                    Text(location?.name ?? "Choose…").font(.headline).lineLimit(1)
                }
                .frame(width: 180, height: 56, alignment: .leading)
            }
            cell(0) {
                if let ref, let scan = location?.primaryScan, let plan = store.floorPlan(ref, scanID: scan.id) {
                    FloorPlanCanvas(plan: plan, style: .thumbnail)
                } else { placeholder("No scan") }
            }
            cell(1) {
                if let ref, let photo = location?.photos.first {
                    StoredImage(url: StoragePaths.photoURL(ref, photo), maxPixel: 400)
                        .frame(width: 180, height: 96).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else { placeholder("No photos") }
            }
            cell(2) { value(UnitsFormatter.dimensions(stats?.width, stats?.length)) }
            cell(3) { value(UnitsFormatter.area(stats?.floorArea), best: isBest(\.floorArea, higher: true, ref: ref)) }
            cell(4) { value(UnitsFormatter.distance(stats?.ceilingHeight), best: isBest(\.ceilingHeight, higher: true, ref: ref)) }
            cell(5) { value(UnitsFormatter.distance(stats?.minCeilingHeight)) }
            cell(6) { value(stats.map { "\($0.windowCount)" } ?? "—") }
            cell(7) { value(stats.map { "\($0.doorCount)" } ?? "—") }
            cell(8) { value(stats.map { "\($0.openingCount)" } ?? "—") }
            cell(9) { value(stats.map { "\($0.objectCount)" } ?? "—") }
            cell(10) { value(location.map { "\($0.cameraPositions.count)" } ?? "—") }
            cell(11) { value(location.map { "\($0.shots.count)" } ?? "—") }
            cell(12) {
                Text(location?.sortedTags.map(\.label).joined(separator: " · ") ?? "")
                    .font(.system(size: 10, weight: .bold).width(.condensed))
                    .foregroundStyle(Theme.accent)
                    .lineLimit(4)
            }
            cell(13) {
                Text(notesSummary(location))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(7)
            }
        }
        .padding(.horizontal, 8)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func cell<Content: View>(_ row: Int, @ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(width: 180, height: Self.rowHeights[row], alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private func value(_ text: String, best: Bool = false) -> some View {
        HStack(spacing: 4) {
            Text(text).font(.system(.body, design: .rounded).monospacedDigit().weight(.semibold))
            if best { Image(systemName: "arrowtriangle.up.fill").font(.caption2).foregroundStyle(Theme.success) }
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(Theme.textTertiary)
    }

    private func isBest(_ key: KeyPath<ScanStats, Double?>, higher: Bool, ref: LocationRef?) -> Bool {
        guard let ref, let mine = store.location(ref)?.primaryScan?.stats[keyPath: key] else { return false }
        let others = selections.compactMap { $0 }.compactMap { store.location($0)?.primaryScan?.stats[keyPath: key] }
        guard others.count > 1 else { return false }
        return higher ? mine >= (others.max() ?? mine) : mine <= (others.min() ?? mine)
    }

    private func notesSummary(_ location: Location?) -> String {
        guard let location else { return "" }
        let quick = location.quickNotes.map(\.text)
        let long = [location.lightingNotes, location.productionNotes, location.notes].filter { !$0.isEmpty }
        return (quick + long).joined(separator: " • ")
    }
}
