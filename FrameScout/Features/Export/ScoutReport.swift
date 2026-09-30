import SwiftUI
import UIKit

/// Everything a scout report needs, resolved up front: ImageRenderer draws synchronously,
/// so photos must already be loaded (async image views would render blank).
struct ScoutReportData {
    var projectName: String
    var location: Location
    var plan: FloorPlan?
    var photos: [(image: UIImage, caption: String)]

    @MainActor
    static func load(_ ref: LocationRef, store: ProjectStore, maxPhotos: Int = 8) -> ScoutReportData? {
        guard let location = store.location(ref) else { return nil }
        let plan = location.primaryScan.flatMap { store.floorPlan(ref, scanID: $0.id) }
        // Viewfinder frames and scan photos first: they are the most informative for a director.
        let ordered = location.photos.sorted { rank($0.source) < rank($1.source) }
        let photos: [(UIImage, String)] = ordered.prefix(maxPhotos).compactMap { photo in
            guard let image = UIImage(contentsOfFile: StoragePaths.photoURL(ref, photo).path)?.downsampled(maxPixel: 900) else { return nil }
            return (image, photo.lensDescription ?? photo.caption)
        }
        return ScoutReportData(projectName: store.project(ref.projectID)?.name ?? "",
                               location: location, plan: plan, photos: photos)
    }

    private static func rank(_ source: PhotoSource) -> Int {
        switch source {
        case .viewfinder: return 0
        case .camera, .library: return 1
        case .scan: return 2
        }
    }
}

enum ScoutReport {
    static let pageSize = CGSize(width: 595, height: 842) // A4 portrait, points

    /// Renders a multi-page PDF. Must run on the main actor (SwiftUI rendering).
    @MainActor
    static func render(_ data: ScoutReportData, to url: URL) throws {
        var pages: [AnyView] = [AnyView(OverviewPage(data: data))]
        if !data.photos.isEmpty {
            for chunk in stride(from: 0, to: data.photos.count, by: 4) {
                pages.append(AnyView(PhotoPage(data: data, photos: Array(data.photos[chunk..<min(chunk + 4, data.photos.count)]))))
            }
        }
        pages.append(AnyView(DetailsPage(data: data)))

        var box = CGRect(origin: .zero, size: pageSize)
        guard let pdf = CGContext(url as CFURL, mediaBox: &box, [
            kCGPDFContextTitle as String: "\(data.location.name) — Scout Report",
            kCGPDFContextCreator as String: "FrameScout",
        ] as CFDictionary) else {
            throw CocoaError(.fileWriteUnknown)
        }
        for (index, page) in pages.enumerated() {
            let content = ReportPageFrame(data: data, page: index + 1, pageCount: pages.count) { page }
                .frame(width: pageSize.width, height: pageSize.height)
                .environment(\.colorScheme, .light)
            let renderer = ImageRenderer(content: content)
            renderer.proposedSize = ProposedViewSize(pageSize)
            renderer.render { _, draw in
                pdf.beginPDFPage(nil)
                draw(pdf)
                pdf.endPDFPage()
            }
        }
        pdf.closePDF()
    }

    @MainActor
    static func renderToTemporaryFile(_ data: ScoutReportData) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Reports", isDirectory: true)
        StoragePaths.ensureDirectory(dir)
        let url = dir.appendingPathComponent("\(StoragePaths.safeName(data.location.name))_Scout_Report.pdf")
        try render(data, to: url)
        return url
    }
}

// MARK: - Page layout (print styling: black on white, amber accents)

private enum Paper {
    static let ink = Color(white: 0.08)
    static let muted = Color(white: 0.42)
    static let rule = Color(white: 0.85)
    static let accent = Color(red: 0.85, green: 0.55, blue: 0.0)
}

private struct ReportPageFrame<Content: View>: View {
    let data: ScoutReportData
    let page: Int
    let pageCount: Int
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("FRAMESCOUT · SCOUT REPORT").font(.system(size: 8, weight: .heavy)).tracking(1.5).foregroundStyle(Paper.accent)
                Spacer()
                Text(data.projectName.uppercased()).font(.system(size: 8, weight: .semibold)).foregroundStyle(Paper.muted)
            }
            Rectangle().fill(Paper.rule).frame(height: 0.5).padding(.vertical, 6)
            content()
            Spacer(minLength: 0)
            Rectangle().fill(Paper.rule).frame(height: 0.5).padding(.bottom, 4)
            HStack {
                Text("\(data.location.name) · generated \(Date().formatted(date: .abbreviated, time: .shortened))")
                Spacer()
                Text("Page \(page) of \(pageCount)")
            }
            .font(.system(size: 7))
            .foregroundStyle(Paper.muted)
        }
        .padding(32)
        .background(Color.white)
    }
}

private struct ReportFigure: View {
    var label: String
    var value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased()).font(.system(size: 7, weight: .bold)).foregroundStyle(Paper.muted)
            Text(value).font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(Paper.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ReportSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased()).font(.system(size: 8, weight: .heavy)).tracking(1).foregroundStyle(Paper.accent)
            content()
        }
    }
}

private struct OverviewPage: View {
    let data: ScoutReportData

    var body: some View {
        let loc = data.location
        let s = loc.primaryScan?.stats
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(loc.name).font(.system(size: 24, weight: .heavy)).foregroundStyle(Paper.ink)
                if !loc.address.isEmpty { Text(loc.address).font(.system(size: 10)).foregroundStyle(Paper.muted) }
                HStack(spacing: 10) {
                    Text("Scanned \(UnitsFormatter.shortDate(loc.dateScanned))")
                    if let c = loc.coordinate { Text(String(format: "GPS %.5f, %.5f", c.latitude, c.longitude)) }
                }
                .font(.system(size: 8)).foregroundStyle(Paper.muted)
                if !loc.tags.isEmpty {
                    Text(loc.sortedTags.map(\.label).joined(separator: "  ·  "))
                        .font(.system(size: 8, weight: .bold)).foregroundStyle(Paper.accent)
                }
            }

            HStack(spacing: 8) {
                ReportFigure(label: "Room", value: UnitsFormatter.dimensions(s?.width, s?.length))
                ReportFigure(label: "Floor area", value: UnitsFormatter.area(s?.floorArea))
                ReportFigure(label: "Ceiling", value: UnitsFormatter.distance(s?.ceilingHeight))
                ReportFigure(label: "Doors / windows", value: s.map { "\($0.doorCount) / \($0.windowCount)" } ?? "—")
            }

            if let plan = data.plan {
                ReportSection(title: "Plan · cameras & shots") {
                    FloorPlanCanvas(plan: plan, overlay: overlay(for: loc), style: .full)
                        .frame(height: 430)
                        .background(Color(white: 0.06), in: RoundedRectangle(cornerRadius: 6))
                    Text("Amber: camera positions · blue: shots · red: subject marks. Grid squares are 1 m. North arrow from the scan compass (approximate).")
                        .font(.system(size: 7)).foregroundStyle(Paper.muted)
                }
            } else {
                Text("No LiDAR scan for this location.").font(.system(size: 10)).foregroundStyle(Paper.muted)
            }

            let quick = loc.quickNotes.prefix(6)
            if !quick.isEmpty {
                ReportSection(title: "Scout notes") {
                    ForEach(Array(quick)) { note in
                        Text("• \(note.text)").font(.system(size: 9)).foregroundStyle(Paper.ink)
                    }
                }
            }
        }
    }

    private func overlay(for loc: Location) -> PlanOverlay {
        var o = PlanOverlay()
        let sid = loc.primaryScan?.id
        for c in loc.cameraPositions where c.scanID == nil || c.scanID == sid {
            o.cameras.append(PlanCameraMarker(id: c.id, label: c.name, rig: c.rig, reach: 3.5))
        }
        for shot in loc.shots where shot.scanID == nil || shot.scanID == sid {
            o.cameras.append(PlanCameraMarker(id: shot.id, label: String(format: "S%02d", shot.number), rig: shot.rig,
                                              isShot: true, reach: max(1.5, (shot.subjectDistance ?? 3) + 0.8)))
            if let subject = shot.subject {
                o.subjects.append(PlanSubjectMarker(id: shot.id, label: String(format: "S%02d", shot.number), point: subject))
            }
        }
        if let north = loc.primaryScan?.northOffset { o.northWorldBearing = 360 - north }
        return o
    }
}

private struct PhotoPage: View {
    let data: ScoutReportData
    let photos: [(image: UIImage, caption: String)]

    var body: some View {
        ReportSection(title: "Reference photos") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 12) {
                ForEach(Array(photos.enumerated()), id: \.offset) { _, photo in
                    VStack(alignment: .leading, spacing: 3) {
                        Image(uiImage: photo.image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 300)
                            .frame(maxWidth: .infinity)
                            .clipped()
                        Text(photo.caption).font(.system(size: 7)).foregroundStyle(Paper.muted).lineLimit(1)
                    }
                }
            }
        }
    }
}

private struct DetailsPage: View {
    let data: ScoutReportData

    var body: some View {
        let loc = data.location
        VStack(alignment: .leading, spacing: 14) {
            if !loc.cameraPositions.isEmpty || !loc.shots.isEmpty {
                ReportSection(title: "Cameras & shots") {
                    row(["", "Lens", "Sensor", "Height", "Pan / tilt", "Notes"], header: true)
                    ForEach(loc.cameraPositions) { c in
                        row([c.name, Optics.formatFocal(c.rig.focalLength), c.rig.sensor.name,
                             UnitsFormatter.distance(c.rig.height), String(format: "%.0f° / %+.0f°", c.rig.pan, c.rig.tilt), c.notes])
                    }
                    ForEach(loc.shots.sorted { $0.number < $1.number }) { s in
                        row(["\(s.code) \(s.title)", Optics.formatFocal(s.rig.focalLength), s.rig.sensor.name,
                             UnitsFormatter.distance(s.rig.height),
                             s.subjectDistance.map { "subject \(UnitsFormatter.distance($0))" } ?? String(format: "%.0f°", s.rig.pan),
                             s.notes])
                    }
                }
            }
            if !loc.measurements.isEmpty {
                ReportSection(title: "Measurements") {
                    ForEach(loc.measurements.prefix(24)) { m in
                        HStack {
                            Text(m.label.isEmpty ? m.kind.label : m.label)
                            Spacer()
                            Text(m.source.label).foregroundStyle(Paper.muted)
                            Text(UnitsFormatter.distance(m.value)).fontWeight(.semibold).monospacedDigit().frame(width: 70, alignment: .trailing)
                        }
                        .font(.system(size: 8.5))
                        .foregroundStyle(Paper.ink)
                    }
                }
            }
            ForEach([("Lighting notes", loc.lightingNotes), ("Production notes", loc.productionNotes), ("General notes", loc.notes)], id: \.0) { title, text in
                if !text.isEmpty {
                    ReportSection(title: title) {
                        Text(text).font(.system(size: 9)).foregroundStyle(Paper.ink).lineLimit(12)
                    }
                }
            }
        }
    }

    private func row(_ cells: [String], header: Bool = false) -> some View {
        let widths: [CGFloat] = [110, 45, 120, 45, 70, .infinity]
        return HStack(alignment: .top, spacing: 6) {
            ForEach(Array(cells.enumerated()), id: \.offset) { i, text in
                Text(text)
                    .lineLimit(2)
                    .frame(maxWidth: widths[i], alignment: .leading)
            }
        }
        .font(.system(size: 8, weight: header ? .bold : .regular))
        .foregroundStyle(header ? Paper.muted : Paper.ink)
        .padding(.vertical, 2)
        .overlay(alignment: .bottom) { Rectangle().fill(Paper.rule).frame(height: 0.5) }
    }
}
