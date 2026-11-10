import Foundation

/// Three-way merge of project JSON, for when the phone and another device (web, desktop) both
/// changed a project since they last synced. Same rules as `web/src/sync/merge.ts`; keep the two
/// in step (`Tests/CoreLogicTests` and `web/tests/merge.test.ts` cover the same cases).
///
/// - A side that didn't change since the base loses to the side that did.
/// - Objects merge key by key; a key removed on one side and untouched on the other is removed.
/// - Arrays whose elements all have an `id` (locations, lights, shots, people, meters…) merge by id:
///   each item merges on its own, items added on either side are kept, an item deleted on one side
///   is deleted unless the other side changed it.
/// - Anything else changed on both sides keeps the local value. `modifiedAt` takes the later date.
enum SyncMerge {
    /// Values as produced by `JSONSerialization`.
    static func merge(base: Any?, local: Any, remote: Any) -> Any {
        merge3(base, local, remote) ?? local
    }

    /// Project → JSON object, the same encoding as project.json.
    static func jsonObject(_ project: Project) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONCoding.encoder.encode(project))
    }

    static func project(from json: Any) throws -> Project {
        try JSONCoding.decoder.decode(Project.self, from: JSONSerialization.data(withJSONObject: json))
    }

    // MARK: Implementation (nil = key or item absent)

    static func equal(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case (nil, _), (_, nil): return false
        case let (x as [String: Any], y as [String: Any]):
            return x.count == y.count && x.allSatisfy { k, v in y[k] != nil && equal(v, y[k]) }
        case let (x as [Any], y as [Any]):
            return x.count == y.count && Swift.zip(x, y).allSatisfy { equal($0, $1) }
        case let (x as String, y as String): return x == y
        case let (x as NSNumber, y as NSNumber):
            return abs(x.doubleValue - y.doubleValue) < 1e-9
        case (is NSNull, is NSNull): return true
        default: return false
        }
    }

    private static func id(_ v: Any) -> String? {
        ((v as? [String: Any])?["id"] as? String)?.uppercased()
    }

    private static func isIdArray(_ v: Any?) -> [[String: Any]]? {
        guard let arr = v as? [Any] else { return nil }
        let items = arr.compactMap { $0 as? [String: Any] }
        return items.count == arr.count && items.allSatisfy({ id($0) != nil }) ? items : nil
    }

    private static func merge3(_ base: Any?, _ local: Any?, _ remote: Any?) -> Any? {
        if equal(local, remote) { return local }
        if equal(base, local) { return remote }
        if equal(base, remote) { return local }
        guard let local, let remote else { return local ?? remote }   // deleted vs changed: keep the change
        if let l = local as? [String: Any], let r = remote as? [String: Any] {
            let b = base as? [String: Any] ?? [:]
            var out: [String: Any] = [:]
            for k in Set(l.keys).union(r.keys) {
                if k == "modifiedAt" { out[k] = later(l[k], r[k]); continue }
                if let v = merge3(b[k], l[k], r[k]) { out[k] = v }
            }
            return out
        }
        if let l = isIdArray(local), let r = isIdArray(remote), base == nil || isIdArray(base) != nil {
            let b = isIdArray(base) ?? []
            func index(_ a: [[String: Any]]) -> [String: [String: Any]] {
                Dictionary(a.map { (id($0)!, $0) }, uniquingKeysWith: { first, _ in first })
            }
            let bi = index(b), li = index(l), ri = index(r)
            var order = r.map { id($0)! }
            for (n, item) in l.enumerated() {
                let itemID = id(item)!
                guard ri[itemID] == nil else { continue }
                let prev = n > 0 ? id(l[n - 1]) : nil
                let at = prev.flatMap { order.firstIndex(of: $0) } ?? -1
                order.insert(itemID, at: at + 1)
            }
            return order.compactMap { merge3(bi[$0], li[$0], ri[$0]) }
        }
        return local
    }

    private static func later(_ a: Any?, _ b: Any?) -> Any {
        let f = ISO8601DateFormatter()
        guard let sa = a as? String, let da = f.date(from: sa) else { return b ?? a ?? NSNull() }
        guard let sb = b as? String, let db = f.date(from: sb) else { return sa }
        return da >= db ? sa : sb
    }
}
