import Foundation

/// Splits a rectangular wall into solid pieces around door/window/opening holes so the exported
/// geometry has real apertures (important for daylight in Unreal). Platform-independent.
enum WallBuilder {
    struct Rect: Equatable {
        var u0: Float, u1: Float, v0: Float, v1: Float
        var width: Float { u1 - u0 }
        var height: Float { v1 - v0 }
    }

    /// - Parameters:
    ///   - width/height: wall size; wall local coordinates are centred (u ∈ ±w/2, v ∈ ±h/2).
    ///   - holes: hole rectangles in the same local coordinates.
    /// - Returns: non-overlapping solid rectangles covering the wall minus the holes.
    static func solidPieces(width: Float, height: Float, holes: [Rect]) -> [Rect] {
        let wall = Rect(u0: -width / 2, u1: width / 2, v0: -height / 2, v1: height / 2)
        let clipped: [Rect] = holes.compactMap { h in
            let r = Rect(u0: max(h.u0, wall.u0), u1: min(h.u1, wall.u1),
                         v0: max(h.v0, wall.v0), v1: min(h.v1, wall.v1))
            return (r.width > 0.01 && r.height > 0.01) ? r : nil
        }
        guard !clipped.isEmpty else { return [wall] }

        var breaks = Set<Float>([wall.u0, wall.u1])
        for h in clipped { breaks.insert(h.u0); breaks.insert(h.u1) }
        let us = breaks.sorted()

        var pieces: [Rect] = []
        for i in 0..<(us.count - 1) {
            let a = us[i], b = us[i + 1]
            guard b - a > 0.001 else { continue }
            let mid = (a + b) / 2
            // Holes spanning this strip, merged along v.
            let covering = clipped.filter { $0.u0 <= mid && $0.u1 >= mid }
                .map { ($0.v0, $0.v1) }
                .sorted { $0.0 < $1.0 }
            var v = wall.v0
            for (h0, h1) in covering {
                if h0 > v + 0.001 { pieces.append(Rect(u0: a, u1: b, v0: v, v1: h0)) }
                v = max(v, h1)
            }
            if wall.v1 > v + 0.001 { pieces.append(Rect(u0: a, u1: b, v0: v, v1: wall.v1)) }
        }
        return mergeHorizontally(pieces)
    }

    /// Joins neighbouring strips with identical vertical extent to keep the mesh light.
    private static func mergeHorizontally(_ pieces: [Rect]) -> [Rect] {
        var result: [Rect] = []
        for p in pieces.sorted(by: { ($0.v0, $0.v1, $0.u0) < ($1.v0, $1.v1, $1.u0) }) {
            if let last = result.last, abs(last.v0 - p.v0) < 0.001, abs(last.v1 - p.v1) < 0.001,
               abs(last.u1 - p.u0) < 0.001 {
                result[result.count - 1].u1 = p.u1
            } else {
                result.append(p)
            }
        }
        return result
    }
}
