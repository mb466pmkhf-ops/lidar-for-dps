import Foundation

/// A named look: a saved copy of a room's lights ("Day", "Night", "Close-up"). The room's `lights`
/// stay the live set every reading and view works from; switching first writes the live lights
/// back into the look you were on, then loads the other one. Same rules as web/src/model/looks.ts.
struct LightingLook: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var lights: [LightFixture] = []
    var scanID: UUID? = nil
}

extension Location {
    private static func inScan(_ id: UUID?, _ scanID: UUID?) -> Bool { id == nil || scanID == nil || id == scanID }

    func looks(scanID: UUID?) -> [LightingLook] { (looks ?? []).filter { Self.inScan($0.scanID, scanID) } }

    func activeLook(scanID: UUID?) -> LightingLook? { looks(scanID: scanID).first { $0.id == activeLookID } }

    private func liveLights(scanID: UUID?) -> [LightFixture] { lightFixtures.filter { Self.inScan($0.scanID, scanID) } }

    /// Saves the live lights as a new look and makes it the one you are on ("save as": the look you
    /// were on keeps what it had when you last switched to or saved it).
    @discardableResult
    mutating func saveLook(named name: String, scanID: UUID?) -> UUID {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let look = LightingLook(name: trimmed.isEmpty ? "Look \(looks(scanID: scanID).count + 1)" : trimmed,
                                lights: liveLights(scanID: scanID), scanID: scanID)
        looks = (looks ?? []) + [look]
        activeLookID = look.id
        return look.id
    }

    /// Keeps the look you are on, then puts the other look's lights in the room. Lights of other scans stay.
    mutating func switchLook(to id: UUID, scanID: UUID?) {
        guard id != activeLookID, let target = looks(scanID: scanID).first(where: { $0.id == id }) else { return }
        let live = liveLights(scanID: scanID)
        if let active = activeLookID {
            looks = looks?.map { l in
                guard l.id == active, Self.inScan(l.scanID, scanID) else { return l }
                var kept = l; kept.lights = live; return kept
            }
        }
        lightFixtures = lightFixtures.filter { !Self.inScan($0.scanID, scanID) } + target.lights
        activeLookID = target.id
    }

    mutating func renameLook(_ id: UUID, to name: String) {
        looks = looks?.map { l in var n = l; if l.id == id { n.name = name }; return n }
    }

    /// Removes a saved look. The lights in the room stay; shots that named it lose the link.
    mutating func deleteLook(_ id: UUID) {
        let left = (looks ?? []).filter { $0.id != id }
        looks = left.isEmpty ? nil : left
        if activeLookID == id { activeLookID = nil }
        shots = shots.map { s in var n = s; if s.lookID == id { n.lookID = nil }; return n }
    }
}
