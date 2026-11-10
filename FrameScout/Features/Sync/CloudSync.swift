import Foundation
import Security
import SwiftUI

/// Keeps projects in step with the web and desktop planner through a Supabase project the owner
/// sets up (Docs/DECISIONS.md D-007). Plain REST over URLSession, no SDK.
///
/// What leaves the phone: project.json and each scan's plan.json (walls, openings, set pieces).
/// Scan meshes, textures and photos never do. Off until the user signs in under Sync.
///
/// Each project keeps the copy last agreed with the server (the merge base) and the server's
/// revision. Writes are compare-and-swap on that revision; when another device got there first
/// the two versions are merged with `SyncMerge` and written again.
@MainActor
final class CloudSync: ObservableObject {
    static let shared = CloudSync()

    enum Status: Equatable {
        case off, signedOut, syncing, synced(Date), offline, error(String)

        var label: String {
            switch self {
            case .off: return "Off"
            case .signedOut: return "Signed out"
            case .syncing: return "Syncing…"
            case .synced: return "Up to date"
            case .offline: return "Offline — will sync later"
            case .error(let m): return m
            }
        }
    }

    struct Config: Codable, Equatable { var url: String; var anonKey: String }

    /// FrameScan's own sync server, used until the user picks another or turns sync off. The anon key
    /// is public by design: row-level security limits every row to its owner (web/supabase/schema.sql).
    static let builtIn = Config(url: "https://nuprvuipspqmhsczdqrk.supabase.co",
                                anonKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im51cHJ2dWlwc3BxbWhzY3pkcXJrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTM5MTYzNDIsImV4cCI6MjEwOTQ5MjM0Mn0.tNQo2XqWI1krE3KMfzuRFzqXSz55eWdgnjgJQFK-jcY")
    struct Session: Codable { var accessToken: String; var refreshToken: String; var expiresAt: Date; var userID: String; var email: String }

    @Published private(set) var status: Status = .off
    @Published private(set) var config: Config?
    @Published private(set) var email: String?

    private weak var store: ProjectStore?
    private var session: Session?
    private var meta: [UUID: Meta] = [:]
    private var timer: Timer?
    private var pushTask: Task<Void, Never>?
    private var running = false
    private var again = false

    /// Per-project sync state, saved next to the projects.
    private struct Meta: Codable {
        var rev: Int?
        var base: Data?          // project JSON as last synced
        var planIDs: [String] = []
        var dirty = false
        var deleted = false
    }

    private static let table = "framescan_projects"
    private let device = "iphone"

    private init() {
        config = (UserDefaults.standard.data(forKey: "sync.config")).flatMap { try? JSONDecoder().decode(Config.self, from: $0) }
            ?? (UserDefaults.standard.bool(forKey: "sync.off") ? nil : Self.builtIn)
        session = Keychain.read("sync.session").flatMap { try? JSONDecoder().decode(Session.self, from: $0) }
        email = session?.email
        meta = (try? Data(contentsOf: Self.metaURL)).flatMap { try? JSONDecoder().decode([UUID: Meta].self, from: $0) } ?? [:]
        status = config == nil ? .off : (session == nil ? .signedOut : .syncing)
    }

    private static var metaURL: URL { StoragePaths.documents.appendingPathComponent("Sync/state.json") }

    private func saveMeta() {
        StoragePaths.ensureDirectory(Self.metaURL.deletingLastPathComponent())
        try? JSONEncoder().encode(meta).write(to: Self.metaURL, options: .atomic)
    }

    // MARK: Wiring

    func attach(_ store: ProjectStore) {
        guard self.store !== store else { return }
        self.store = store
        store.onProjectWritten = { [weak self] project in self?.markDirty(project.id) }
        store.onProjectDeleted = { [weak self] id in self?.markDeleted(id) }
        // Projects that existed before sync was switched on upload on the first run.
        for p in store.projects where meta[p.id] == nil { meta[p.id] = Meta(dirty: true) }
        saveMeta()
        startTimer()
        syncSoon(after: 0.5)
    }

    func appBecameActive() { syncSoon(after: 0.2) }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.syncSoon(after: 0) }
        }
    }

    private func markDirty(_ id: UUID) {
        var m = meta[id] ?? Meta()
        m.dirty = true
        meta[id] = m
        saveMeta()
        syncSoon(after: 1.5)
    }

    private func markDeleted(_ id: UUID) {
        guard var m = meta[id] else { return }
        if m.rev == nil { meta[id] = nil } else { m.deleted = true; m.dirty = true; meta[id] = m }
        saveMeta()
        syncSoon(after: 0.5)
    }

    private func syncSoon(after seconds: Double) {
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            if seconds > 0 { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
            guard !Task.isCancelled else { return }
            await self?.sync()
        }
    }

    // MARK: Account

    func configure(url: String, anonKey: String) {
        let c = Config(url: url.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/")),
                       anonKey: anonKey.trimmingCharacters(in: .whitespacesAndNewlines))
        config = c
        UserDefaults.standard.set(try? JSONEncoder().encode(c), forKey: "sync.config")
        UserDefaults.standard.removeObject(forKey: "sync.off")
        status = session == nil ? .signedOut : .syncing
    }

    func turnOff() {
        signOut()
        config = nil
        UserDefaults.standard.removeObject(forKey: "sync.config")
        UserDefaults.standard.set(true, forKey: "sync.off")
        status = .off
    }

    func signIn(email: String, password: String, createAccount: Bool) async throws {
        let path = createAccount ? "signup" : "token?grant_type=password"
        try await authenticate(path: path, body: ["email": email, "password": password])
        // A new account (or a different one) uploads everything on this phone.
        if let store { for p in store.projects { meta[p.id] = Meta(dirty: true) } }
        saveMeta()
        await sync()
    }

    func signOut() {
        session = nil
        email = nil
        Keychain.delete("sync.session")
        meta = [:]
        saveMeta()
        if config != nil { status = .signedOut }
    }

    private func authenticate(path: String, body: [String: String]) async throws {
        guard let config, let url = URL(string: "\(config.url)/auth/v1/\(path)") else { throw SyncError.notConfigured }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = json["error_description"] as? String ?? json["msg"] as? String ?? json["message"] as? String ?? "Sign-in failed"
            if (response as? HTTPURLResponse)?.statusCode == 400 && path.hasPrefix("token?grant_type=refresh") { signOut() }
            throw SyncError.server(message)
        }
        guard let access = json["access_token"] as? String, let refresh = json["refresh_token"] as? String else {
            throw SyncError.server("Check your email to confirm the account, then sign in.")
        }
        let user = json["user"] as? [String: Any]
        let s = Session(accessToken: access, refreshToken: refresh,
                        expiresAt: Date().addingTimeInterval(json["expires_in"] as? Double ?? 3600),
                        userID: user?["id"] as? String ?? "", email: user?["email"] as? String ?? body["email"] ?? "")
        session = s
        email = s.email
        Keychain.write("sync.session", try JSONEncoder().encode(s))
    }

    private func token() async throws -> String {
        guard let s = session else { throw SyncError.signedOut }
        if s.expiresAt.timeIntervalSinceNow < 60 {
            try await authenticate(path: "token?grant_type=refresh_token", body: ["refresh_token": s.refreshToken])
        }
        return session!.accessToken
    }

    // MARK: REST

    private func rest(_ method: String, _ query: String, body: Any? = nil, prefer: String? = nil) async throws -> Any? {
        guard let config, let url = URL(string: "\(config.url)/rest/v1/\(Self.table)?\(query)") else { throw SyncError.notConfigured }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer { req.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { signOut(); throw SyncError.signedOut }
        if code == 409 { throw SyncError.conflict }
        guard (200..<300).contains(code) else { throw SyncError.server("Sync server: \(code) \(String(data: data, encoding: .utf8) ?? "")") }
        return data.isEmpty ? nil : try JSONSerialization.jsonObject(with: data)
    }

    private func fetchRow(_ id: UUID) async throws -> [String: Any]? {
        (try await rest("GET", "select=*&id=eq.\(id.uuidString)") as? [[String: Any]])?.first
    }

    // MARK: Sync

    func sync() async {
        guard config != nil, session != nil, let store else { return }
        if running { again = true; return }
        running = true
        defer { running = false }
        if case .synced = status {} else { status = .syncing }
        do {
            repeat {
                again = false
                let heads = try await rest("GET", "select=id,rev,deleted") as? [[String: Any]] ?? []
                for head in heads {
                    guard let idString = head["id"] as? String, let id = UUID(uuidString: idString) else { continue }
                    let rev = (head["rev"] as? NSNumber)?.intValue ?? 0
                    if (head["deleted"] as? Bool) == true {
                        if store.project(id) != nil && meta[id]?.dirty != true {
                            store.onProjectDeleted = nil
                            store.deleteProject(id)
                            store.onProjectDeleted = { [weak self] id in self?.markDeleted(id) }
                        }
                        if meta[id]?.dirty != true { meta[id] = nil }
                        continue
                    }
                    if meta[id]?.rev == rev && store.project(id) != nil { continue }
                    if let row = try await fetchRow(id) { try absorb(row, id: id, store: store) }
                }
                for (id, m) in meta where m.dirty { try await push(id, store: store) }
                saveMeta()
            } while again
            status = .synced(Date())
        } catch SyncError.signedOut {
            status = .signedOut
        } catch let error as URLError {
            status = error.code == .notConnectedToInternet || error.code == .networkConnectionLost || error.code == .timedOut ? .offline : .error(error.localizedDescription)
        } catch {
            status = .error((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
        saveMeta()
    }

    /// Takes the server's copy: replaces an unchanged local project, or merges with local edits.
    private func absorb(_ row: [String: Any], id: UUID, store: ProjectStore) throws {
        guard let doc = row["doc"] else { return }
        let rev = (row["rev"] as? NSNumber)?.intValue ?? 0
        var m = meta[id] ?? Meta()
        var result = doc
        if m.dirty, let local = store.project(id) {
            let base = m.base.flatMap { try? JSONSerialization.jsonObject(with: $0) }
            result = SyncMerge.merge(base: base, local: try SyncMerge.jsonObject(local), remote: doc)
        }
        var project = try SyncMerge.project(from: result)
        project.id = id
        writePlans(row["plans"] as? [String: Any] ?? [:], for: project)
        store.applyRemote(project)
        m.rev = rev
        m.base = try JSONSerialization.data(withJSONObject: doc)
        m.planIDs = Array((row["plans"] as? [String: Any] ?? [:]).keys)
        meta[id] = m
    }

    /// Plans from other devices (only ever the phone's own scans) go where the plan editor reads them.
    private func writePlans(_ plans: [String: Any], for project: Project) {
        for location in project.locations {
            let ref = LocationRef(projectID: project.id, locationID: location.id)
            for scan in location.scans {
                let url = StoragePaths.scanFile(ref, scanID: scan.id, .plan)
                guard !FileManager.default.fileExists(atPath: url.path),
                      let plan = plans[scan.id.uuidString] ?? plans[scan.id.uuidString.lowercased()],
                      let data = try? JSONSerialization.data(withJSONObject: plan) else { continue }
                StoragePaths.ensureDirectory(url.deletingLastPathComponent())
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private func localPlans(_ project: Project) -> [String: Any] {
        var out: [String: Any] = [:]
        for location in project.locations {
            let ref = LocationRef(projectID: project.id, locationID: location.id)
            for scan in location.scans {
                let url = StoragePaths.scanFile(ref, scanID: scan.id, .plan)
                if let data = try? Data(contentsOf: url), let json = try? JSONSerialization.jsonObject(with: data) {
                    out[scan.id.uuidString] = json
                }
            }
        }
        return out
    }

    private func push(_ id: UUID, store: ProjectStore) async throws {
        guard var m = meta[id] else { return }
        if m.deleted {
            if let rev = m.rev {
                let rows = try await rest("PATCH", "id=eq.\(id.uuidString)&rev=eq.\(rev)&select=id",
                                          body: ["deleted": true, "rev": rev + 1, "updated_by": device], prefer: "return=representation") as? [Any]
                if rows?.count == 1 { meta[id] = nil }
            } else {
                meta[id] = nil
            }
            return
        }
        guard let project = store.project(id) else { meta[id] = nil; return }
        let doc = try SyncMerge.jsonObject(project)
        let plans = localPlans(project)
        let planIDs = plans.keys.sorted()
        let sent = { (rev: Int) in
            m.rev = rev
            m.base = try? JSONSerialization.data(withJSONObject: doc)
            m.planIDs = planIDs
            // Edits made while this was uploading keep the project marked for the next round.
            m.dirty = (try? SyncMerge.jsonObject(store.project(id) ?? project)).map { !SyncMerge.equal($0, doc) } ?? false
            self.meta[id] = m
        }
        if let rev = m.rev {
            var body: [String: Any] = ["name": project.name, "doc": doc, "rev": rev + 1, "deleted": false,
                                       "updated_by": device, "updated_at": ISO8601DateFormatter().string(from: Date())]
            if planIDs != m.planIDs.sorted() { body["plans"] = plans }
            let rows = try await rest("PATCH", "id=eq.\(id.uuidString)&rev=eq.\(rev)&select=id", body: body, prefer: "return=representation") as? [Any]
            if rows?.count == 1 { sent(rev + 1) } else if let row = try await fetchRow(id) { try absorb(row, id: id, store: store); again = true }
        } else {
            do {
                _ = try await rest("POST", "select=id", body: ["id": id.uuidString, "name": project.name, "doc": doc, "plans": plans,
                                                              "rev": 1, "deleted": false, "updated_by": device], prefer: "return=minimal")
                sent(1)
            } catch SyncError.conflict {
                if let row = try await fetchRow(id) { try absorb(row, id: id, store: store); again = true }
            }
        }
    }

    enum SyncError: LocalizedError {
        case notConfigured, signedOut, conflict, server(String)
        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Add the sync server first."
            case .signedOut: return "Signed out — sign in again."
            case .conflict: return "Changed on another device."
            case .server(let m): return m
            }
        }
    }
}

/// Minimal Keychain storage for the sign-in token.
enum Keychain {
    private static let service = "FrameScout.sync"

    static func write(_ key: String, _ data: Data) {
        delete(key)
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: key, kSecValueData as String: data,
                                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        SecItemAdd(q as CFDictionary, nil)
    }

    static func read(_ key: String) -> Data? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: key, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? out as? Data : nil
    }

    static func delete(_ key: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
        SecItemDelete(q as CFDictionary)
    }
}
