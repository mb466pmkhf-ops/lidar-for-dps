import AuthenticationServices
import SwiftUI

/// Account and sync with the FrameScan planner on the web and desktop. The same server and account
/// are used on every device. Sign in with Apple, Google or an email account.
struct SyncSettingsView: View {
    @ObservedObject var sync = CloudSync.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.webAuthenticationSession) private var webAuth

    private enum Mode: String, CaseIterable { case signIn = "Sign in", create = "Create account" }

    @State private var mode: Mode = .signIn
    @State private var url = ""
    @State private var anonKey = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var code = ""
    /// Set after sign-up while the account waits for its confirmation email.
    @State private var pendingEmail: String?
    @State private var busy = false
    @State private var message: String?
    @State private var notice: String?
    @State private var editingServer = false
    @State private var confirmDelete = false

    static let minPassword = 8

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Sign in to continue the lighting plan on the web or the desktop app. The plan, lights, people, meters and the 2D floor plan sync. Scan meshes and photos stay on this iPhone.")
                        .font(.fsCaption)
                        .foregroundStyle(Theme.textSecondary)
                }

                if sync.config == nil || editingServer {
                    serverSection
                } else if let signedIn = sync.email {
                    Section {
                        LabeledContent("Account", value: signedIn)
                        LabeledContent("Status", value: sync.status.label)
                        Button("Sync now") { Task { await sync.sync() } }
                        Button("Sign out", role: .destructive) { sync.signOut() }
                    } footer: {
                        Text("Changes sync within a few seconds while the app is open. Edits made on two devices at once are merged item by item.")
                    }
                    Section { Button("Server…") { startEditingServer() } }
                    Section {
                        Button("Delete account…", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("Removes the account and every project synced to it from the server. Projects on this iPhone stay here.")
                    }
                } else if let pending = pendingEmail {
                    verifySection(pending)
                } else {
                    providerSection
                    emailSection
                    Section { Button("Server…") { startEditingServer() } }
                }

                if let notice {
                    Section { Text(notice).font(.fsCaption).foregroundStyle(Theme.textSecondary) }
                }
                if let message {
                    Section { Text(message).font(.fsCaption).foregroundStyle(Theme.danger) }
                }
            }
            .disabled(busy)
            .fsScreen()
            .navigationTitle("Account & sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete account", role: .destructive) { run { try await sync.deleteAccount() } }
                Button("Keep my account", role: .cancel) {}
            } message: {
                Text("Your account and every project synced to it are removed from the server, on all your devices. Projects on this iPhone stay. This can't be undone.")
            }
        }
    }

    // MARK: Sections

    private var providerSection: some View {
        Section {
            Button { signIn(with: .apple) } label: {
                Label("Continue with Apple", systemImage: "apple.logo").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(.primary).foregroundStyle(Color(uiColor: .systemBackground))
            .controlSize(.large)
            Button { signIn(with: .google) } label: {
                Label("Continue with Google", systemImage: "g.circle").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).controlSize(.large)
        } footer: {
            Text("Use the same account in the web planner and the desktop app.")
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
    }

    private var emailSection: some View {
        Section {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: mode) { _, _ in message = nil; confirm = "" }

            TextField("Email", text: $email)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.emailAddress).textContentType(.emailAddress)
            SecureField("Password", text: $password).textContentType(mode == .create ? .newPassword : .password)
            if mode == .create {
                SecureField("Confirm password", text: $confirm).textContentType(.newPassword)
                if let problem = passwordProblem {
                    Text(problem).font(.fsCaption).foregroundStyle(Theme.textSecondary)
                }
                Button("Create account") { createAccount() }.disabled(!validEmail || passwordProblem != nil)
            } else {
                Button("Sign in") { signIn() }.disabled(!validEmail || password.isEmpty)
            }
        } header: {
            Text("Or use email")
        } footer: {
            if mode == .create {
                Text("We'll email you to confirm the address before the account can sync.")
            }
        }
    }

    private func verifySection(_ address: String) -> some View {
        Section {
            Text("We sent an email to \(address). Tap the link in it, or type the code from it here.")
                .font(.fsCaption)
            TextField("Code from the email", text: $code)
                .keyboardType(.numberPad).textContentType(.oneTimeCode)
            Button("Confirm") { verify(address) }.disabled(code.filter(\.isNumber).count < 6)
            Button("I tapped the link — sign in") {
                pendingEmail = nil
                mode = .signIn
                email = address
                notice = nil
            }
            Button("Send the email again") { resend(address) }
            Button("Use another email", role: .cancel) { pendingEmail = nil; code = ""; notice = nil }
        } header: {
            Text("Confirm your email")
        }
    }

    private var serverSection: some View {
        Section {
            TextField("https://xxxx.supabase.co", text: $url)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
            TextField("Anon (public) key", text: $anonKey)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("Save server") {
                sync.configure(url: url, anonKey: anonKey)
                editingServer = false
            }
            .disabled(url.isEmpty || anonKey.isEmpty)
            if sync.config != CloudSync.builtIn {
                Button("Use the FrameScan server") {
                    sync.configure(url: CloudSync.builtIn.url, anonKey: CloudSync.builtIn.anonKey)
                    editingServer = false
                }
            }
            if sync.config != nil {
                Button("Turn sync off", role: .destructive) { sync.turnOff(); editingServer = false }
            }
            if sync.config != nil {
                Button("Back", role: .cancel) { editingServer = false }
            }
        } header: {
            Text("Server")
        } footer: {
            Text("The FrameScan server is set up already. Only enter a URL and anon key if you run your own Supabase project (steps in web/README.md).")
        }
    }

    // MARK: Checks

    private var validEmail: Bool {
        let e = email.trimmingCharacters(in: .whitespaces)
        return e.contains("@") && e.contains(".") && !e.hasPrefix("@")
    }

    private var passwordProblem: String? {
        if password.count < Self.minPassword { return "At least \(Self.minPassword) characters." }
        if confirm.isEmpty { return "Type the password again to confirm it." }
        if confirm != password { return "The passwords don't match." }
        return nil
    }

    // MARK: Actions

    private func startEditingServer() {
        url = sync.config?.url ?? ""
        anonKey = sync.config?.anonKey ?? ""
        editingServer = true
    }

    private func run(_ work: @escaping () async throws -> Void) {
        busy = true
        message = nil
        Task {
            do { try await work() }
            catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin { /* closed the sheet */ }
            catch { message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
            busy = false
        }
    }

    private func signIn() {
        let address = email.trimmingCharacters(in: .whitespaces)
        run { try await sync.signIn(email: address, password: password); password = "" }
    }

    private func createAccount() {
        let address = email.trimmingCharacters(in: .whitespaces)
        run {
            let signedIn = try await sync.createAccount(email: address, password: password)
            password = ""; confirm = ""
            if !signedIn { pendingEmail = address; code = "" }
        }
    }

    private func verify(_ address: String) {
        run { try await sync.verifyEmail(email: address, code: code); pendingEmail = nil; code = ""; notice = nil }
    }

    private func resend(_ address: String) {
        run { try await sync.resendConfirmation(email: address); notice = "Sent. Use the code from the newest email." }
    }

    private func signIn(with provider: CloudSync.Provider) {
        run {
            let start = try await sync.oauthStart(provider)
            let callback = try await webAuth.authenticate(using: start.url, callbackURLScheme: CloudSync.callbackScheme)
            try await sync.oauthFinish(callback: callback, verifier: start.verifier)
        }
    }
}
