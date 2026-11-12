import Foundation

/// Grip catalogue: flag and frame sizes, and the rags (drapes) that go on them. Same tables as
/// web/src/model/grip.ts; web/tests/grip.test.ts parses this file, so keep ids, names and numbers identical.
///
/// Every figure is an estimate (general crew practice): stops for nets, silks and grids are what crews
/// quote, and the real rag is metered on the day. Diffusion rags reuse the unit gel figures (LEE
/// datasheets) so a frame of full white cuts the same as a sheet of it on a lamp.
struct GripSize: Identifiable, Hashable {
    var id: String
    var name: String
    /// Frame width and height (m).
    var width: Double
    var height: Double
    /// A floppy: a second panel of the same size that opens down from the bottom edge.
    var floppy: Bool = false
    /// Stands a frame this size goes up on: one, or two (one at each side).
    var stands: Int
    /// Grip kinds this size is sold as.
    var kinds: [LightKind]
}

struct Drape: Identifiable, Hashable {
    enum Pattern: String { case checker, net }

    var id: String
    var name: String
    /// Grip kinds this rag works as; the first is used when it's picked on something else.
    var kinds: [LightKind]
    /// Share of the light that gets through (0…1).
    var transmission: Double
    /// Share of what gets through that is scattered soft (1 = full diffusion; 0 = a net, it only cuts).
    var scatter: Double
    /// Share thrown back off the lit face.
    var reflectance: Double
    /// Colour for drawing (sRGB hex).
    var color: Int
    var pattern: Pattern? = nil
    var note: String
}

/// Optics a rag (and any frame gels) gives a board.
struct DrapeOptics: Hashable {
    var transmission: Double
    var scatter: Double
    var reflectance: Double
}

enum GripCatalog {
    static let gripKinds: [LightKind] = [.bounce, .negative, .flag, .diffusion]

    static let sizes: [GripSize] = [
        GripSize(id: "flag-12x18", name: "12×18\" flag", width: 0.3, height: 0.46, stands: 1, kinds: [.flag, .negative, .diffusion]),
        GripSize(id: "flag-18x24", name: "18×24\" flag", width: 0.46, height: 0.61, stands: 1, kinds: [.flag, .negative, .diffusion]),
        GripSize(id: "flag-24x36", name: "24×36\" flag", width: 0.61, height: 0.91, stands: 1, kinds: [.flag, .negative, .diffusion]),
        GripSize(id: "floppy-4x4", name: "4×4 floppy", width: 1.22, height: 1.22, floppy: true, stands: 1, kinds: [.flag, .negative]),
        GripSize(id: "frame-4x4", name: "4×4 frame", width: 1.22, height: 1.22, stands: 1, kinds: [.bounce, .negative, .flag, .diffusion]),
        GripSize(id: "frame-6x6", name: "6×6 frame", width: 1.83, height: 1.83, stands: 1, kinds: [.bounce, .negative, .flag, .diffusion]),
        GripSize(id: "frame-8x8", name: "8×8 frame", width: 2.44, height: 2.44, stands: 2, kinds: [.bounce, .negative, .flag, .diffusion]),
        GripSize(id: "frame-12x12", name: "12×12 frame", width: 3.66, height: 3.66, stands: 2, kinds: [.bounce, .negative, .flag, .diffusion]),
    ]

    static let drapes: [Drape] = [
        Drape(id: "white-board", name: "White bounce board", kinds: [.bounce], transmission: 0, scatter: 0, reflectance: 0.8, color: 0xf4f4f2, note: "General crew practice. Foam-core or white card."),
        Drape(id: "ultrabounce-white", name: "Ultrabounce (white side)", kinds: [.bounce], transmission: 0, scatter: 0, reflectance: 0.85, color: 0xf7f7f5, note: "General crew practice. Opaque; the back is black."),
        Drape(id: "griffolyn-white", name: "Griffolyn (white side)", kinds: [.bounce], transmission: 0, scatter: 0, reflectance: 0.75, color: 0xeeeeea, note: "General crew practice. Opaque laminate; the back is black."),
        Drape(id: "muslin-bleached", name: "Bleached muslin", kinds: [.bounce, .diffusion], transmission: 0.2, scatter: 1, reflectance: 0.65, color: 0xefede6, note: "General crew practice. Soft, slightly lossy bounce; lets some light through."),
        Drape(id: "muslin-unbleached", name: "Unbleached muslin", kinds: [.bounce, .diffusion], transmission: 0.15, scatter: 1, reflectance: 0.55, color: 0xe2d6bc, note: "General crew practice. Warms the bounce a little (colour not in the readings)."),
        Drape(id: "checkerboard", name: "Checkerboard (white/silver)", kinds: [.bounce], transmission: 0, scatter: 0, reflectance: 0.85, color: 0xdcdcdc, pattern: .checker, note: "General crew practice. Punchier than white; the silver squares add a harder edge the readings treat as soft."),
        Drape(id: "silver-lame", name: "Silver lamé", kinds: [.bounce], transmission: 0, scatter: 0, reflectance: 0.9, color: 0xc9ccd0, note: "General crew practice. Specular and directional; readings treat it as a soft bounce, so the spot it throws is brighter than shown."),
        Drape(id: "gold-lame", name: "Gold lamé", kinds: [.bounce], transmission: 0, scatter: 0, reflectance: 0.75, color: 0xd4b46a, note: "General crew practice. Warms the bounce (colour not in the readings)."),
        Drape(id: "solid", name: "Solid (black duvetyne)", kinds: [.flag, .negative], transmission: 0, scatter: 0, reflectance: 0.03, color: 0x0a0a0a, note: "General crew practice. Blocks the light; a little sheen on the lit face."),
        Drape(id: "ultrabounce-black", name: "Ultrabounce (black side)", kinds: [.negative, .flag], transmission: 0, scatter: 0, reflectance: 0.05, color: 0x101010, note: "General crew practice. Opaque; the white side faces away."),
        Drape(id: "griffolyn-black", name: "Griffolyn (black side)", kinds: [.negative, .flag], transmission: 0, scatter: 0, reflectance: 0.05, color: 0x121212, note: "General crew practice. Opaque laminate; the white side faces away."),
        Drape(id: "silk", name: "Silk", kinds: [.diffusion], transmission: 0.35, scatter: 1, reflectance: 0.35, color: 0xf5f3ee, note: "General crew practice: about 1½ stops."),
        Drape(id: "china-silk", name: "China silk", kinds: [.diffusion], transmission: 0.6, scatter: 0.75, reflectance: 0.2, color: 0xf6f4ef, note: "General crew practice: about ¾ stop, keeps some of the source's shape."),
        Drape(id: "grid-quarter", name: "¼ grid cloth", kinds: [.diffusion], transmission: 0.7, scatter: 0.85, reflectance: 0.2, color: 0xf3f3f1, note: "General crew practice: about ½ stop."),
        Drape(id: "grid-half", name: "½ grid cloth", kinds: [.diffusion], transmission: 0.5, scatter: 1, reflectance: 0.3, color: 0xf2f2f0, note: "General crew practice: about 1 stop."),
        Drape(id: "grid-full", name: "Full grid cloth", kinds: [.diffusion], transmission: 0.35, scatter: 1, reflectance: 0.35, color: 0xf0f0ee, note: "General crew practice: about 1½ stops."),
        Drape(id: "frost-light", name: "Opal / ¼ frost", kinds: [.diffusion], transmission: 0.8, scatter: 0.5, reflectance: 0.15, color: 0xf6f6f6, note: "Same figure as the light diffusion gel (LEE datasheet)."),
        Drape(id: "white-half", name: "½ white diffusion", kinds: [.diffusion], transmission: 0.6, scatter: 0.85, reflectance: 0.25, color: 0xf3f3f3, note: "Same figure as the medium diffusion gel (LEE datasheet)."),
        Drape(id: "white-full", name: "Full white diffusion", kinds: [.diffusion], transmission: 0.36, scatter: 1, reflectance: 0.35, color: 0xf1f1f1, note: "Same figure as the heavy diffusion gel (LEE datasheet)."),
        Drape(id: "net-single", name: "Single net", kinds: [.diffusion, .flag], transmission: 0.7, scatter: 0, reflectance: 0, color: 0x1a1a1a, pattern: .net, note: "General crew practice: about ½ stop. Cuts without softening."),
        Drape(id: "net-double", name: "Double net", kinds: [.diffusion, .flag], transmission: 0.5, scatter: 0, reflectance: 0, color: 0x141414, pattern: .net, note: "General crew practice: about 1 stop. Cuts without softening."),
        Drape(id: "clear", name: "Clear (gel only)", kinds: [.diffusion], transmission: 1, scatter: 0, reflectance: 0, color: 0xffffff, note: "An empty frame for a colour or ND gel."),
    ]

    /// The rag a board of this kind gets when none is picked: matches the board's built-in optics.
    static func defaultDrapeID(for kind: LightKind) -> String? {
        switch kind {
        case .bounce: return "white-board"
        case .negative, .flag: return "solid"
        case .diffusion: return "grid-half"
        default: return nil
        }
    }

    /// Ready-made grip in the Add menus (phone and web): size plus rag.
    struct Preset: Identifiable, Hashable {
        var id: String
        var label: String
        var size: String
        var drape: String
    }
    static let presets: [Preset] = [
        Preset(id: "floppy", label: "4×4 floppy", size: "floppy-4x4", drape: "solid"),
        Preset(id: "net-24x36", label: "24×36 net", size: "flag-24x36", drape: "net-single"),
        Preset(id: "silk-6x6", label: "6×6 silk", size: "frame-6x6", drape: "silk"),
        Preset(id: "ultrabounce-8x8", label: "8×8 Ultrabounce", size: "frame-8x8", drape: "ultrabounce-white"),
        Preset(id: "grid-12x12", label: "12×12 grid cloth", size: "frame-12x12", drape: "grid-half"),
    ]
    static func preset(id: String) -> Preset? { presets.first { $0.id == id } }

    static func size(id: String?) -> GripSize? { id.flatMap { id in sizes.first { $0.id == id } } }
    static func drape(id: String?) -> Drape? { id.flatMap { id in drapes.first { $0.id == id } } }
    static func sizes(for kind: LightKind) -> [GripSize] { sizes.filter { $0.kinds.contains(kind) } }
    static func drapes(for kind: LightKind) -> [Drape] { drapes.filter { $0.kinds.contains(kind) } }

    /// Gels that can go on a frame: colour correction and ND. Diffusion is the rag itself.
    static var frameGels: [LightFilter] { FixtureLibrary.filters.filter { $0.diffusion == nil } }

    /// Stops of loss for a transmission, to the nearest third: "about 1⅓ stops".
    static func stopsText(_ t: Double) -> String {
        guard t > 0 else { return "blocks it" }
        if t >= 0.97 { return "no loss" }
        let thirds = Int((-log2(t) * 3).rounded())
        let whole = thirds / 3, part = ["", "⅓", "⅔"][thirds % 3]
        return "about \(whole > 0 ? String(whole) : "")\(part) stop\(thirds > 3 ? "s" : "")"
    }
}

extension LightFixture {
    /// The size, if it was picked and still matches the board.
    var gripSize: GripSize? {
        guard let s = GripCatalog.size(id: gripSizeID), abs(s.width - width) < 0.01 else { return nil }
        return s
    }

    /// The rag on this board, if one was picked and it works as the board's kind.
    var drape: Drape? {
        guard GripCatalog.gripKinds.contains(kind), let d = GripCatalog.drape(id: drapeID), d.kinds.contains(kind) else { return nil }
        return d
    }

    /// Frame gels on a diffusion frame.
    var frameGels: [LightFilter] {
        guard kind == .diffusion else { return [] }
        return (filterIDs ?? []).compactMap(FixtureLibrary.filter(id:)).filter { $0.diffusion == nil }
    }

    /// Optics from the picked rag and gels; nil leaves the board's built-in figures for its kind.
    var drapeOptics: DrapeOptics? {
        let gels = frameGels
        guard drape != nil || !gels.isEmpty,
              let base = drape ?? GripCatalog.drape(id: GripCatalog.defaultDrapeID(for: kind)) else { return nil }
        let gelPass = gels.reduce(1) { $0 * $1.transmission }
        return DrapeOptics(transmission: base.transmission * gelPass, scatter: base.scatter, reflectance: base.reflectance)
    }

    /// The board's face: width, and the bottom and top edges (m above the floor). A floppy opened drops
    /// its second panel below the first, so the top edge stays where it was.
    var gripSpan: (width: Double, bottom: Double, top: Double) {
        let h = boardHeight ?? (kind == .flag ? min(width, 0.9) : width)
        let open = floppyOpen == true && gripSize?.floppy == true
        return (width, height - h / 2 - (open ? h : 0), height + h / 2)
    }

    /// Stands a board goes up on: frames 8×8 and up sit on their ears between two.
    var gripStandCount: Int { GripCatalog.gripKinds.contains(kind) && width >= 2.4 ? 2 : 1 }

    /// Name for lists and the plan: "12×12 Silk", "4×4 floppy (open)", "Bounce".
    var gripLabel: String {
        var parts: [String] = []
        let size = gripSize
        if let size {
            if size.floppy { parts.append(size.name + (floppyOpen == true ? " (open)" : "")) }
            else { parts.append(size.name.replacingOccurrences(of: #" (frame|flag)$"#, with: "", options: .regularExpression)) }
        }
        if let d = drape { parts.append(d.name) }
        else if size?.floppy != true { parts.append(kind.label) }
        let gels = frameGels
        if !gels.isEmpty { parts.append("+ " + gels.map(\.name).joined(separator: ", ")) }
        return parts.filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Applies a size: width, height and the floppy flag.
    mutating func applyGripSize(_ s: GripSize) {
        let before = self
        gripSizeID = s.id
        width = s.width
        boardHeight = s.height
        if !s.floppy { floppyOpen = nil }
        // Keep the frame clear of the floor: the centre at least half the frame (plus a little) up.
        let lowest = s.height / 2 + 0.15
        if height < lowest { height = (lowest * 100).rounded() / 100 }
        renameIfAutomatic(from: before)
    }

    /// Applies a rag, switching the board's kind when the rag doesn't work as the current one.
    mutating func applyDrape(_ d: Drape) {
        let before = self
        if !d.kinds.contains(kind), let first = d.kinds.first { kind = first }
        drapeID = d.id
        if kind != .diffusion { filterIDs = nil }
        renameIfAutomatic(from: before)
    }

    /// Opens or closes a floppy.
    mutating func setFloppyOpen(_ open: Bool) {
        let before = self
        floppyOpen = open ? true : nil
        renameIfAutomatic(from: before)
    }

    /// Keeps a name the user typed; replaces one the app made.
    private mutating func renameIfAutomatic(from before: LightFixture) {
        let auto: Set<String> = [before.gripLabel, before.kind.label]
        let base = before.name.replacingOccurrences(of: #" \d+$"#, with: "", options: .regularExpression)
        if auto.contains(base) || auto.contains(before.name) { name = gripLabel }
    }
}
