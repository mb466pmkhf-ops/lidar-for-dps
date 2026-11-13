import CryptoKit
import Foundation
import Security
import SwiftUI

/// Keeps projects in step with the web and desktop planner through a Supabase project the owner
/// sets up (Docs/DECISIONS.md D-007). Plain REST over URLSession, no SDK.
///
/// What leaves the phone: project.json and each scan's plan.json (walls, openings, set pieces).
/// Plans merge like projects (doors, windows and set pieces by id), so set pieces added by hand on
/// the desktop and on the phone both survive.
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
        /// The plans (scan id → plan JSON) as last synced: the merge base for set-piece edits.
        var planBase: Data?
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
        // A session and revisions from another server mean nothing here.
        if c != config { signOut() }
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

    func signIn(email: String, password: String) async throws {
        guard try await authenticate(path: "token?grant_type=password", body: ["email": email, "password": password]) else {
            throw SyncError.server("Sign-in failed")
        }
        await didSignIn()
    }

    /// Creates an email account. Returns false when the server wants the email confirmed first: the
    /// user then taps the link in the email or types its code into `verifyEmail`.
    func createAccount(email: String, password: String) async throws -> Bool {
        guard try await authenticate(path: "signup", body: ["email": email, "password": password]) else { return false }
        await didSignIn()
        return true
    }

    /// Confirms a new account with the code from the confirmation email, which also signs in.
    func verifyEmail(email: String, code: String) async throws {
        let token = code.filter { !$0.isWhitespace }
        guard try await authenticate(path: "verify", body: ["type": "signup", "email": email, "token": token]) else {
            throw SyncError.server("That code didn't work. Check the newest email, or tap its link and then sign in.")
        }
        await didSignIn()
    }

    func resendConfirmation(email: String) async throws {
        _ = try await post(path: "resend", body: ["type": "signup", "email": email])
    }

    // MARK: Apple and Google

    enum Provider: String { case apple, google }

    /// Where the sign-in page sends the browser back to. Must be listed under Supabase → Authentication
    /// → URL Configuration → Redirect URLs. ASWebAuthenticationSession catches it, so the scheme needs
    /// no Info.plist entry and works with a free personal team.
    static let callbackScheme = "framescan"
    static let callbackURL = "framescan://auth-callback"

    struct OAuthStart { let url: URL; let verifier: String }

    /// The provider's sign-in page, through Supabase, with a PKCE challenge so only this app can use
    /// the code that comes back.
    func oauthStart(_ provider: Provider) async throws -> OAuthStart {
        guard let config else { throw SyncError.notConfigured }
        try await requireProvider(provider, config: config)
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw SyncError.server("Couldn't start sign-in") }
        let verifier = Data(bytes).base64URL
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        var c = URLComponents(string: "\(config.url)/auth/v1/authorize")
        c?.queryItems = [URLQueryItem(name: "provider", value: provider.rawValue),
                         URLQueryItem(name: "redirect_to", value: Self.callbackURL),
                         URLQueryItem(name: "code_challenge", value: challenge),
                         URLQueryItem(name: "code_challenge_method", value: "s256")]
        guard let url = c?.url else { throw SyncError.notConfigured }
        return OAuthStart(url: url, verifier: verifier)
    }

    /// Fails with plain words when the server hasn't switched the provider on, instead of the raw
    /// error page the sign-in sheet would otherwise show. Unknown answers let the attempt go ahead.
    private func requireProvider(_ provider: Provider, config: Config) async throws {
        guard let url = URL(string: "\(config.url)/auth/v1/settings") else { return }
        var req = URLRequest(url: url)
        req.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let external = json["external"] as? [String: Any],
              let enabled = external[provider.rawValue] as? Bool else { return }
        if !enabled {
            throw SyncError.server("\(provider == .apple ? "Apple" : "Google") sign-in isn't switched on for this server yet. Use email for now.")
        }
    }

    /// Takes the callback URL the sign-in page redirected to and swaps its code for a session.
    func oauthFinish(callback: URL, verifier: String) async throws {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let error = value("error_description") ?? value("error") {
            throw SyncError.server(error.replacingOccurrences(of: "+", with: " "))
        }
        guard let code = value("code") else { throw SyncError.server("Sign-in was cancelled.") }
        guard try await authenticate(path: "token?grant_type=pkce", body: ["auth_code": code, "code_verifier": verifier]) else {
            throw SyncError.server("Sign-in failed")
        }
        await didSignIn()
    }

    /// A new account (or a different one) uploads everything on this phone.
    private func didSignIn() async {
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

    /// Deletes the account and every project synced to it on the server, then signs out.
    /// Projects on this iPhone stay. Needs `delete_my_account()` from web/supabase/schema.sql.
    func deleteAccount() async throws {
        guard let config, let url = URL(string: "\(config.url)/rest/v1/rpc/delete_my_account") else { throw SyncError.notConfigured }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("{}".utf8)
        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 { throw SyncError.server("This sync server can't delete accounts yet. Its owner needs to run the newest web/supabase/schema.sql.") }
        guard (200..<300).contains(code) else {
            throw SyncError.server("Couldn't delete the account: \(code) \(String(data: data, encoding: .utf8) ?? "")")
        }
        signOut()
    }

    private func post(path: String, body: [String: String]) async throws -> [String: Any] {
        guard let config, let url = URL(string: "\(config.url)/auth/v1/\(path)") else { throw SyncError.notConfigured }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            if (response as? HTTPURLResponse)?.statusCode == 400 && path.hasPrefix("token?grant_type=refresh") { signOut() }
            throw SyncError.server(Self.authMessage(json))
        }
        return json
    }

    /// Plain words for the auth server's errors.
    static func authMessage(_ json: [String: Any]) -> String {
        switch json["error_code"] as? String {
        case "email_not_confirmed": return "Confirm your email first: tap the link we sent, or enter its code under Create account."
        case "invalid_credentials": return "Wrong email or password."
        case "user_already_exists", "email_exists": return "There's already an account with this email. Sign in instead."
        case "weak_password": return "Choose a longer password (at least 8 characters)."
        case "otp_expired": return "That code has expired. Send a new email and use the newest code."
        case "over_email_send_rate_limit": return "Too many emails just now. Wait a minute and try again."
        default: return json["error_description"] as? String ?? json["msg"] as? String ?? json["message"] as? String ?? "Sign-in failed"
        }
    }

    /// Returns false when the server answered without a session (a sign-up waiting for its email).
    @discardableResult
    private func authenticate(path: String, body: [String: String]) async throws -> Bool {
        let json = try await post(path: path, body: body)
        guard let access = json["access_token"] as? String, let refresh = json["refresh_token"] as? String else { return false }
        let user = json["user"] as? [String: Any]
        let s = Session(accessToken: access, refreshToken: refresh,
                        expiresAt: Date().addingTimeInterval(json["expires_in"] as? Double ?? 3600),
                        userID: user?["id"] as? String ?? "", email: user?["email"] as? String ?? body["email"] ?? "")
        session = s
        email = s.email
        Keychain.write("sync.session", try JSONEncoder().encode(s))
        return true
    }

    private func token() async throws -> String {
        guard let s = session else { throw SyncError.signedOut }
        if s.expiresAt.timeIntervalSinceNow < 60 {
            guard try await authenticate(path: "token?grant_type=refresh_token", body: ["refresh_token": s.refreshToken]) else { throw SyncError.signedOut }
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
        let remotePlans = Self.upperKeys(row["plans"] as? [String: Any] ?? [:])
        let basePlans = m.planBase.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        let ownPlans = localPlans(store.project(id) ?? project, store: store)
        let plans = SyncMerge.merge(base: basePlans, local: ownPlans, remote: remotePlans) as? [String: Any] ?? remotePlans
        store.applyRemote(project)
        writePlans(plans, local: ownPlans, for: project, store: store)
        m.rev = rev
        m.base = try JSONSerialization.data(withJSONObject: doc)
        m.planIDs = Array(remotePlans.keys)
        m.planBase = try? JSONSerialization.data(withJSONObject: remotePlans)
        // Set pieces edited here and not on the server yet go up on the next push.
        if !SyncMerge.equal(plans, remotePlans) { m.dirty = true }
        meta[id] = m
    }

    /// Plans keyed by scan id in upper case, as `UUID.uuidString` writes them.
    static func upperKeys(_ plans: [String: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        for (k, v) in plans { out[k.uppercased()] = v }
        return out
    }

    /// Merged plans go where the plan editor reads them, replacing this phone's copy when it differs.
    private func writePlans(_ plans: [String: Any], local: [String: Any], for project: Project, store: ProjectStore) {
        for location in project.locations {
            let ref = LocationRef(projectID: project.id, locationID: location.id)
            for scan in location.scans {
                let key = scan.id.uuidString
                guard let plan = plans[key], !SyncMerge.equal(plan, local[key]),
                      let data = try? JSONSerialization.data(withJSONObject: plan) else { continue }
                if let decoded = try? JSONCoding.decoder.decode(FloorPlan.self, from: data) {
                    store.applyRemotePlan(decoded, ref, scanID: scan.id)
                } else {
                    // Not readable as a plan by this build: keep it as it came, but never over our own.
                    let url = StoragePaths.scanFile(ref, scanID: scan.id, .plan)
                    guard !FileManager.default.fileExists(atPath: url.path) else { continue }
                    StoragePaths.ensureDirectory(url.deletingLastPathComponent())
                    try? data.write(to: url, options: .atomic)
                }
            }
        }
    }

    /// This phone's plans, including edits made by hand that are still waiting to be written.
    private func localPlans(_ project: Project, store: ProjectStore) -> [String: Any] {
        var out: [String: Any] = [:]
        for location in project.locations {
            let ref = LocationRef(projectID: project.id, locationID: location.id)
            for scan in location.scans {
                if let plan = store.floorPlan(ref, scanID: scan.id), let data = try? JSONCoding.encoder.encode(plan),
                   let json = try? JSONSerialization.jsonObject(with: data) {
                    out[scan.id.uuidString] = json
                } else if let data = try? Data(contentsOf: StoragePaths.scanFile(ref, scanID: scan.id, .plan)),
                          let json = try? JSONSerialization.jsonObject(with: data) {
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
        let plans = localPlans(project, store: store)
        let planIDs = plans.keys.sorted()
        let basePlans = m.planBase.flatMap { try? JSONSerialization.jsonObject(with: $0) }
        let sent = { (rev: Int) in
            m.rev = rev
            m.base = try? JSONSerialization.data(withJSONObject: doc)
            m.planIDs = planIDs
            m.planBase = try? JSONSerialization.data(withJSONObject: plans)
            // Edits made while this was uploading keep the project marked for the next round.
            let now = store.project(id) ?? project
            let projectChanged = (try? SyncMerge.jsonObject(now)).map { !SyncMerge.equal($0, doc) } ?? false
            m.dirty = projectChanged || !SyncMerge.equal(self.localPlans(now, store: store), plans)
            self.meta[id] = m
        }
        if let rev = m.rev {
            var body: [String: Any] = ["name": project.name, "doc": doc, "rev": rev + 1, "deleted": false,
                                       "updated_by": device, "updated_at": ISO8601DateFormatter().string(from: Date())]
            // Plans go up whenever they changed since the last sync (a set piece moved, a door added).
            if basePlans == nil || !SyncMerge.equal(plans, basePlans) { body["plans"] = plans }
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

private extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

/// Keychain storage for the sign-in token. Kept on this device only: not in backups or on a new phone.
enum Keychain {
    private static let service = "FrameScout.sync"

    static func write(_ key: String, _ data: Data) {
        delete(key)
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: key, kSecValueData as String: data,
                                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
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
