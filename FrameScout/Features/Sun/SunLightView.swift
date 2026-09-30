import SwiftUI

struct SunLightView: View {
    let ref: LocationRef
    @EnvironmentObject private var store: ProjectStore
    @StateObject private var locator = LocationProvider()
    @State private var day = Date()
    @State private var minutes: Double = 16 * 60
    @State private var latText = ""
    @State private var lonText = ""

    private var location: Location? { store.location(ref) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let location, let coordinate = location.coordinate {
                    timeControls(location)
                    let date = selectedDate(location)
                    let sun = SolarCalculator.position(date: date, latitude: coordinate.latitude, longitude: coordinate.longitude)
                    let events = SolarCalculator.events(on: date, latitude: coordinate.latitude, longitude: coordinate.longitude, timeZone: location.timeZone)
                    sunReadout(sun, events: events, zone: location.timeZone)
                    SunPathDiagram(path: SolarCalculator.path(on: date, latitude: coordinate.latitude, longitude: coordinate.longitude,
                                                              timeZone: location.timeZone),
                                   current: sun, zone: location.timeZone)
                        .frame(height: 300)
                        .card()
                    planSection(location, sun: sun)
                    windowSection(location, coordinate: coordinate, date: date)
                } else {
                    coordinateEntry
                }
                Text("Sun positions use the NOAA solar algorithm and work offline. Direction inside the scan relies on the compass reading taken during scanning — indoors it can be off by 10–20°, so calibrate north if you know the true orientation. This is planning information, not a lighting simulation.")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding()
        }
        .fsScreen()
        .navigationTitle("Sun & Light")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let calendar = Calendar.current
            let comps = calendar.dateComponents([.hour, .minute], from: Date())
            minutes = Double((comps.hour ?? 16) * 60 + (comps.minute ?? 0))
        }
    }

    private func selectedDate(_ location: Location) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = location.timeZone
        return calendar.startOfDay(for: day).addingTimeInterval(minutes * 60)
    }

    // MARK: Sections

    private func timeControls(_ location: Location) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DatePicker("Shooting day", selection: $day, displayedComponents: .date)
            HStack {
                Text(String(format: "%02d:%02d", Int(minutes) / 60, Int(minutes) % 60))
                    .font(.fsBigValue)
                Spacer()
                Text(location.timeZone.identifier).font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Slider(value: $minutes, in: 0...1439, step: 5)
            HStack {
                ForEach([7, 9, 12, 15, 16, 18, 20], id: \.self) { h in
                    TagChip(text: "\(h):00", selected: Int(minutes) == h * 60) { minutes = Double(h * 60) }
                }
            }
        }
        .card()
    }

    private func sunReadout(_ sun: SolarPosition, events: SunEvents, zone: TimeZone) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                StatView(label: "Sun direction", value: String(format: "%.0f° %@", sun.azimuth, SolarCalculator.compassName(sun.azimuth)), highlight: true)
                StatView(label: "Elevation", value: String(format: "%.1f°", sun.elevation),
                         detail: sun.elevation < 0 ? "below horizon" : (sun.elevation < 6 ? "golden hour" : nil))
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    StatView(label: "Sunrise", value: UnitsFormatter.time(events.sunrise, in: zone))
                    StatView(label: "Solar noon", value: UnitsFormatter.time(events.solarNoon, in: zone),
                             detail: String(format: "%.0f° high", events.noonElevation))
                    StatView(label: "Sunset", value: UnitsFormatter.time(events.sunset, in: zone))
                }
                GridRow {
                    StatView(label: "Golden AM ends", value: UnitsFormatter.time(events.goldenHourMorningEnd, in: zone))
                    StatView(label: "Golden PM", value: UnitsFormatter.time(events.goldenHourEveningStart, in: zone))
                    StatView(label: "Civil dusk", value: UnitsFormatter.time(events.civilDusk, in: zone))
                }
            }
        }
        .card()
    }

    @ViewBuilder
    private func planSection(_ location: Location, sun: SolarPosition) -> some View {
        if let scan = location.primaryScan, let plan = store.floorPlan(ref, scanID: scan.id) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Sun on the scan", systemImage: "map")
                if let north = scan.northOffset {
                    let lit = litWindows(plan: plan, north: north, sun: sun)
                    FloorPlanCanvas(plan: plan, overlay: sunOverlay(north: north, sun: sun, lit: lit), style: .full)
                        .frame(height: 300)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: 10))
                    Text(lit.isEmpty ? "No window is in direct sun at this time."
                                     : "\(lit.count) window\(lit.count == 1 ? "" : "s") in direct sun (highlighted).")
                        .font(.subheadline)
                    northCalibration(scan)
                } else {
                    Text("This scan has no compass reading, so the sun can't be placed on it. Set north manually:")
                        .font(.subheadline).foregroundStyle(Theme.textSecondary)
                    northCalibration(scan)
                }
            }
            .card()
        }
    }

    private func sunOverlay(north: Double, sun: SolarPosition, lit: Set<UUID>) -> PlanOverlay {
        var overlay = PlanOverlay()
        overlay.northWorldBearing = (360 - north).truncatingRemainder(dividingBy: 360)
        overlay.sunWorldBearing = sun.azimuth - north
        overlay.sunElevation = sun.elevation
        overlay.litWindows = lit
        overlay.showDimensions = false
        return overlay
    }

    private func northCalibration(_ scan: ScanRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SliderRow(title: "Scan north offset", value: Binding(
                get: { scan.northOffset ?? 0 },
                set: { v in
                    store.updateLocation(ref) { loc in
                        if let i = loc.scans.firstIndex(where: { $0.id == scan.id }) { loc.scans[i].northOffset = v }
                    }
                }), range: 0...359, step: 1, format: { String(format: "%.0f°", $0) })
            if let measured = scan.measuredNorthOffset, abs((scan.northOffset ?? measured) - measured) > 0.5 {
                Button("Reset to compass reading (\(Int(measured))°)") {
                    store.updateLocation(ref) { loc in
                        if let i = loc.scans.firstIndex(where: { $0.id == scan.id }) { loc.scans[i].northOffset = measured }
                    }
                }
                .font(.caption)
            }
        }
    }

    private func litWindows(plan: FloorPlan, north: Double, sun: SolarPosition) -> Set<UUID> {
        Set(plan.windows.filter { w in
            let facing = plan.outwardBearing(of: w) + north
            return WindowLight.evaluate(facing: facing, sun: sun) > 0.02
        }.map(\.id))
    }

    @ViewBuilder
    private func windowSection(_ location: Location, coordinate: GeoCoordinate, date: Date) -> some View {
        if let scan = location.primaryScan, let north = scan.northOffset,
           let plan = store.floorPlan(ref, scanID: scan.id), !plan.windows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Natural light through windows", systemImage: "window.vertical.open")
                ForEach(Array(plan.windows.enumerated()), id: \.element.id) { index, window in
                    let facing = (plan.outwardBearing(of: window) + north).truncatingRemainder(dividingBy: 360)
                    let now = WindowLight.evaluate(facing: facing,
                                                   sun: SolarCalculator.position(date: date, latitude: coordinate.latitude, longitude: coordinate.longitude))
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("Window \(index + 1)").font(.headline)
                            Text("faces \(SolarCalculator.compassName(facing)) (\(Int(facing))°) · \(UnitsFormatter.distance(window.length)) wide")
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                            Spacer()
                            if now > 0.02 {
                                Label("\(Int(now * 100))%", systemImage: "sun.max.fill").foregroundStyle(Theme.sun).font(.caption.bold())
                            }
                        }
                        Text(directSunWindows(facing: facing, coordinate: coordinate, date: date, zone: location.timeZone))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Divider()
                }
            }
            .card()
        }
    }

    /// "Direct sun 14:30–18:45" for the selected day, sampled every 15 minutes.
    private func directSunWindows(facing: Double, coordinate: GeoCoordinate, date: Date, zone: TimeZone) -> String {
        let path = SolarCalculator.path(on: date, latitude: coordinate.latitude, longitude: coordinate.longitude, timeZone: zone, minutes: 15)
        var ranges: [(Date, Date)] = []
        var start: Date?
        var last: Date?
        for (t, p) in path {
            if WindowLight.evaluate(facing: facing, sun: p) > 0.05 {
                if start == nil { start = t }
                last = t
            } else if let s = start, let l = last {
                ranges.append((s, l))
                start = nil
            }
        }
        if let s = start, let l = last { ranges.append((s, l)) }
        guard !ranges.isEmpty else { return "No direct sun on this day (indirect / sky light only)." }
        return "Direct sun " + ranges.map { "\(UnitsFormatter.time($0.0, in: zone))–\(UnitsFormatter.time($0.1, in: zone))" }.joined(separator: ", ")
    }

    private var coordinateEntry: some View {
        VStack(alignment: .leading, spacing: 12) {
            RequirementBanner(title: "Location needed",
                              message: "Sun calculations need the location's latitude and longitude. GPS works offline.",
                              systemImage: "location")
            Button {
                Task {
                    if let fix = await locator.currentFix() {
                        store.updateLocation(ref) { loc in
                            loc.coordinate = fix.coordinate
                            if loc.address.isEmpty, let a = fix.address { loc.address = a }
                            if let tz = fix.timeZoneIdentifier { loc.timeZoneIdentifier = tz }
                        }
                    }
                }
            } label: {
                Label(locator.isLocating ? "Locating…" : "Use current GPS position", systemImage: "location.fill")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .foregroundStyle(.black)
            if let error = locator.lastError { Text(error).font(.caption).foregroundStyle(Theme.danger) }
            HStack {
                TextField("Latitude", text: $latText).keyboardType(.numbersAndPunctuation)
                TextField("Longitude", text: $lonText).keyboardType(.numbersAndPunctuation)
                Button("Set") {
                    if let lat = Double(latText), let lon = Double(lonText), abs(lat) <= 90, abs(lon) <= 180 {
                        store.updateLocation(ref) { $0.coordinate = GeoCoordinate(latitude: lat, longitude: lon) }
                    }
                }
            }
            .textFieldStyle(.roundedBorder)
        }
        .card()
    }
}

/// Polar sun-path plot: centre = overhead, rim = horizon, north up.
struct SunPathDiagram: View {
    let path: [(Date, SolarPosition)]
    let current: SolarPosition
    let zone: TimeZone

    var body: some View {
        Canvas { ctx, size in
            let radius = min(size.width, size.height) / 2 - 22
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            func point(_ p: SolarPosition) -> CGPoint {
                let r = radius * CGFloat((90 - max(p.elevation, 0)) / 90)
                let a = p.azimuth * .pi / 180
                return CGPoint(x: c.x + r * CGFloat(sin(a)), y: c.y - r * CGFloat(cos(a)))
            }
            for e in [0.0, 30, 60] {
                let r = radius * CGFloat((90 - e) / 90)
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                           with: .color(.white.opacity(e == 0 ? 0.35 : 0.12)), lineWidth: 1)
            }
            for (label, az) in [("N", 0.0), ("E", 90), ("S", 180), ("W", 270)] {
                let a = az * .pi / 180
                ctx.draw(Text(label).font(.caption.bold()).foregroundColor(label == "N" ? Theme.danger : Theme.textSecondary),
                         at: CGPoint(x: c.x + (radius + 12) * CGFloat(sin(a)), y: c.y - (radius + 12) * CGFloat(cos(a))))
            }
            var line = Path()
            for (i, sample) in path.enumerated() where sample.1.elevation > 0 {
                let p = point(sample.1)
                if i == 0 || path[i - 1].1.elevation <= 0 { line.move(to: p) } else { line.addLine(to: p) }
            }
            ctx.stroke(line, with: .color(Theme.sun.opacity(0.7)), lineWidth: 2)
            let calendar: Calendar = {
                var cal = Calendar(identifier: .gregorian)
                cal.timeZone = zone
                return cal
            }()
            for sample in path where sample.1.elevation > 0 && calendar.component(.minute, from: sample.0) == 0 {
                let hour = calendar.component(.hour, from: sample.0)
                guard hour % 2 == 0 else { continue }
                let p = point(sample.1)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4)), with: .color(Theme.sun))
                ctx.draw(Text("\(hour)").font(.system(size: 9)).foregroundColor(Theme.textSecondary),
                         at: CGPoint(x: p.x, y: p.y - 9))
            }
            if current.elevation > 0 {
                let p = point(current)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 10, y: p.y - 10, width: 20, height: 20)), with: .color(Theme.sun))
            } else {
                ctx.draw(Text("Sun below horizon").font(.caption).foregroundColor(Theme.textSecondary), at: c)
            }
        }
    }
}
