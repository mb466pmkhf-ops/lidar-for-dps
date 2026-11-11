import Foundation

/// A lighting setup the user saved themselves ("my presets"), to drop their own favourite
/// arrangement in again with one tap. Units are kept relative to an anchor, either a person (seen
/// from the camera) or a window, and are placed and levelled again for the new scene when used.
/// Like the built-in `LightingSetup`s it is a starting point, and levels are estimates.
/// Port: web/src/model/presets.ts. Keep the fields, maths and wording the same.
struct LightingPreset: Codable, Hashable, Identifiable {
    enum Anchor: String, Codable, CaseIterable, Identifiable {
        /// Round a person, relative to the camera looking at them.
        case person
        /// Relative to a window: through it from outside, or just inside it.
        case window
        var id: String { rawValue }
        var label: String { self == .person ? "Round a person" : "At a window" }
    }

    struct Unit: Codable, Hashable {
        /// The saved unit: fixture, modifier, colour, gels, barn doors. Where it stands, its aim and
        /// level come from the fields below.
        var light: LightFixture
        // Person anchor.
        /// Degrees from the camera direction, seen from the person (+ = the key's side).
        var angle: Double = 0
        /// Metres from the person (shortened if a wall is in the way).
        var distance: Double = 2
        /// Height above the person's eyes (m).
        var rise: Double = 0.5
        // Window anchor.
        /// Metres along the window from its centre (+ = right, standing inside facing the window).
        var along: Double = 0
        /// Metres out from the glass (+ = outside, − = inside the room).
        var out: Double = 0
        /// Height above the floor (m).
        var height: Double = 1.5
        // Both.
        /// Pan in degrees relative to "aimed at the person" (person) or "aimed straight in" (window).
        var panOffset: Double = 0
        /// Tilt in degrees. nil aims at the person's face (person anchor only).
        var tilt: Double? = nil
        /// Level against the camera's key: 0 = at the set stop, 2 = two stops under, −1 = one over.
        /// nil keeps the saved dimmer.
        var stopsUnderKey: Double? = nil

        /// Back and edge lights are metered facing the unit, the rest towards camera.
        var isRim: Bool { abs(angle) > 100 }
    }

    var id: UUID = UUID()
    var name: String
    var anchor: Anchor
    /// Person presets: false puts the key on whichever side has more room, like the built-in
    /// setups; true keeps the sides exactly as saved.
    var keepSides: Bool = false
    var units: [Unit]

    /// One line per unit, for menus: "Key 45° 2.2 m · Fill −40° …".
    var summary: String {
        units.map { u in
            let name = u.light.name
            switch anchor {
            case .person: return "\(name) \(Int(u.angle.rounded()))°"
            case .window: return u.out > 0 ? "\(name) outside" : "\(name) inside"
            }
        }.joined(separator: " · ")
    }
}

// MARK: Saving

extension LightingPreset {
    /// Saves `lights` relative to `person`, seen from `camera` (nil: from the way they face). Each
    /// unit lit onto the face keeps its level as stops against the key, so it follows the stop
    /// when used again; the rest keep their dimmer.
    static func capture(name: String, lights: [LightFixture], person: PrevisCharacter, camera: PlanPoint?,
                        exposure: ExposureSettings, plan: FloorPlan?,
                        windowTransmission: Double = SceneDisplay.defaultWindowTransmission) -> LightingPreset {
        let p = person.position
        let towardCamera = camera.map { PlanGeometry.bearing(from: p, to: $0) } ?? person.facing
        let face = LightingCalculator.Point(p, height: max(0.3, person.eyeHeight - 0.03))
        let scene = LightingCalculator.Scene(lights: lights, plan: plan, windowTransmission: windowTransmission)
        var units: [Unit] = lights.map { light in
            var u = Unit(light: template(light, stripping: person.name))
            let d = max(0.1, p.distance(to: light.position))
            u.angle = round1(wrap180(PlanGeometry.bearing(from: p, to: light.position) - towardCamera))
            u.distance = round2(d)
            u.rise = round2(light.height - face.y)
            let pan = wrap180(light.pan - PlanGeometry.bearing(from: light.position, to: p))
            u.panOffset = abs(pan) < 3 ? 0 : round1(pan)
            let aimedTilt = -atan2(light.height - face.y, d) * 180 / .pi
            u.tilt = u.panOffset == 0 && abs(light.tilt - aimedTilt) < 3 ? nil : round1(light.tilt)
            if light.kind.emits, light.isOn {
                let normal = u.isRim ? (LightingCalculator.Point(light.position, height: light.height) - face).normalized
                                     : LightingCalculator.direction(bearing: towardCamera, tilt: 0)
                let lux = LightingCalculator.reading(at: face, normal: normal, scene: scene).contributions
                    .filter { $0.lightID == light.id }.reduce(0) { $0 + $1.lux }
                if lux > 0.5 { u.stopsUnderKey = round1(log2(exposure.keyLux / lux)) }
            }
            return u
        }
        // Saved with the key on the + side, so it can be mirrored to whichever side has room.
        let key = units.first { $0.light.role == .key } ?? units.first { $0.stopsUnderKey != nil } ?? units.first
        if let key, key.angle < 0 { units = units.map(mirrored) }
        return LightingPreset(name: name, anchor: .person, units: units)
    }

    /// Saves `lights` relative to `window`: along it, out from the glass and how high.
    static func capture(name: String, lights: [LightFixture], window: PlanSegment, plan: FloorPlan) -> LightingPreset {
        let frame = WindowFrame(window, plan: plan)
        let units: [Unit] = lights.map { light in
            var u = Unit(light: template(light, stripping: nil))
            let v = light.position - frame.centre
            u.along = round2(v.x * frame.right.x + v.z * frame.right.z)
            u.out = round2(v.x * frame.outward.x + v.z * frame.outward.z)
            u.height = round2(light.height)
            u.panOffset = round1(wrap180(light.pan - frame.inward))
            u.tilt = round1(light.tilt)
            return u
        }
        return LightingPreset(name: name, anchor: .window, units: units)
    }

    /// The unit as stored: no id, place, aim or scan; the person's name taken off its label.
    private static func template(_ light: LightFixture, stripping person: String?) -> LightFixture {
        var t = light
        t.id = UUID()
        if let person, t.name.hasSuffix(" · \(person)") { t.name = String(t.name.dropLast(person.count + 3)) }
        t.position = .zero
        t.pan = 0
        t.scanID = nil
        return t
    }
}

// MARK: Using

extension LightingPreset {
    /// Places the preset round `person`, seen from `camera` (nil: from the way they face), levelled
    /// for `exposure`. A window preset uses the window nearest the person.
    func build(for person: PrevisCharacter, camera: PlanPoint?, exposure: ExposureSettings, plan: FloorPlan?,
               windowTransmission: Double = SceneDisplay.defaultWindowTransmission) -> LightingSetup.Result {
        switch anchor {
        case .window:
            guard let plan, let window = Self.nearestWindow(to: person.position, in: plan) else {
                return LightingSetup.Result(lights: [], notes: ["This preset needs a window in the plan"])
            }
            return build(at: window, plan: plan, scanID: person.scanID)
        case .person:
            break
        }
        let p = person.position
        let towardCamera = camera.map { PlanGeometry.bearing(from: p, to: $0) } ?? person.facing
        let face = LightingCalculator.Point(p, height: max(0.3, person.eyeHeight - 0.03))
        let faceNormal = LightingCalculator.direction(bearing: towardCamera, tilt: 0)
        let key = exposure.keyLux
        let side: Double = keepSides ? 1
            : LightingSetup.room(from: p, bearing: towardCamera + 60, plan: plan) >= LightingSetup.room(from: p, bearing: towardCamera - 60, plan: plan) ? 1 : -1
        var lights: [LightFixture] = []
        var notes: [String] = []
        for unit in units {
            let u = side < 0 ? Self.mirrored(unit) : unit
            let bearing = towardCamera + u.angle
            let d = min(u.distance, max(0.6, LightingSetup.room(from: p, bearing: bearing, plan: plan) - 0.4))
            let at = p + PlanPoint.unit(bearing: bearing) * d
            var light = u.light
            light.id = UUID()
            light.name = "\(u.light.name) · \(person.name)"
            light.position = at
            light.pan = wrap360(PlanGeometry.bearing(from: at, to: p) + u.panOffset)
            light.height = max(0.3, face.y + u.rise)
            light.tilt = u.tilt ?? -atan2(light.height - face.y, d) * 180 / .pi
            light.scanID = person.scanID
            if let stops = u.stopsUnderKey, light.kind.emits {
                let target = key / pow(2, stops)
                let normal = u.isRim ? (LightingCalculator.Point(at, height: light.height) - face).normalized : faceNormal
                let solution = LightingCalculator.solveOutput(for: light, target: target, at: face, normal: normal, allLights: [light],
                                                              plan: plan, windowTransmission: windowTransmission)
                notes.append(LightingSetup.level(&light, with: solution, name: u.light.name, target: target))
            }
            lights.append(light)
        }
        return LightingSetup.Result(lights: lights, notes: notes)
    }

    /// Places the preset at `window`, at the saved dimmer levels.
    func build(at window: PlanSegment, plan: FloorPlan, scanID: UUID?) -> LightingSetup.Result {
        let frame = WindowFrame(window, plan: plan)
        var lights: [LightFixture] = []
        var notes: [String] = []
        for u in units {
            var light = u.light
            light.id = UUID()
            light.position = frame.centre + frame.right * u.along + frame.outward * u.out
            light.height = u.height
            light.pan = wrap360(frame.inward + u.panOffset)
            light.tilt = u.tilt ?? light.tilt
            light.scanID = scanID
            if light.kind.emits {
                notes.append("\(u.light.name): \(light.profile.name) at \(Int((light.dimmer * 100).rounded())) %, \(u.out > 0 ? "outside" : "inside")")
            }
            lights.append(light)
        }
        return LightingSetup.Result(lights: lights, notes: notes)
    }

    static func nearestWindow(to p: PlanPoint, in plan: FloorPlan) -> PlanSegment? {
        plan.windows.min { PlanGeometry.closestPoint(on: $0.a, $0.b, to: p).distance(to: p) < PlanGeometry.closestPoint(on: $1.a, $1.b, to: p).distance(to: p) }
    }
}

// MARK: Library file

extension LightingPreset {
    /// What a preset list is stored and shared as (the same JSON on the phone and the planner).
    struct Library: Codable {
        var framescanPresets: Int? = 1
        var presets: [LightingPreset]
    }

    static func encode(_ presets: [LightingPreset]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(Library(presets: presets)) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Reads a stored or shared list. Pasted text from the planner works too; anything else gives nil.
    static func decode(_ text: String) -> [LightingPreset]? {
        let data = Data(text.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        if let lib = try? JSONDecoder().decode(Library.self, from: data) { return lib.presets }
        if let one = try? JSONDecoder().decode(LightingPreset.self, from: data) { return [one] }
        return nil
    }
}

// MARK: Helpers

private extension LightingPreset {
    /// Mirror across the camera axis: angles, aim and the barn doors swap sides.
    static func mirrored(_ u: Unit) -> Unit {
        var m = u
        m.angle = -u.angle
        m.panOffset = -u.panOffset
        if var doors = u.light.barnDoors { swap(&doors.left, &doors.right); m.light.barnDoors = doors }
        return m
    }
}

/// A window's centre and directions: out of the room, to the right standing inside facing it.
private struct WindowFrame {
    var centre: PlanPoint
    var outward: PlanPoint
    var right: PlanPoint
    /// Bearing aimed straight in through the window.
    var inward: Double

    init(_ window: PlanSegment, plan: FloorPlan) {
        let out = plan.outwardBearing(of: window)
        centre = window.midpoint
        outward = PlanPoint.unit(bearing: out)
        right = PlanPoint.unit(bearing: out + 90)
        inward = wrap360(out + 180)
    }
}

private func wrap180(_ d: Double) -> Double {
    var a = d.truncatingRemainder(dividingBy: 360)
    if a > 180 { a -= 360 }
    if a <= -180 { a += 360 }
    return a
}
private func wrap360(_ d: Double) -> Double { let a = d.truncatingRemainder(dividingBy: 360); return a < 0 ? a + 360 : a }
private func round1(_ v: Double) -> Double { (v * 10).rounded() / 10 }
private func round2(_ v: Double) -> Double { (v * 100).rounded() / 100 }
