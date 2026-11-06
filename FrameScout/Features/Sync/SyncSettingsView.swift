import SwiftUI

/// Sync with the FrameScan planner on the web and desktop. Off until set up; the same server and
/// account are used on every device.
struct SyncSettingsView: View {
    @ObservedObject var sync = CloudSync.shared
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var anonKey = ""
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var message: String?
    @State private var editingServer = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Continue the lighting plan on the web or the desktop app. The plan, lights, people, meters and the 2D floor plan sync. Scan meshes and photos stay on this iPhone.")
                        .font(.fsCaption)
                        .foregroundStyle(Theme.textSecondary)
                }

                if sync.config == nil || editingServer {
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
                    } header: {
                        Text("Server")
                    } footer: {
                        Text("The FrameScan server is set up already. Only enter a URL and anon key if you run your own Supabase project (steps in web/README.md).")
                    }
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
                } else {
                    Section {
                        TextField("Email", text: $email)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.emailAddress).textContentType(.emailAddress)
                        SecureField("Password", text: $password).textContentType(.password)
                        Button("Sign in") { run(create: false) }.disabled(busy || email.isEmpty || password.isEmpty)
                        Button("Create account") { run(create: true) }.disabled(busy || email.isEmpty || password.count < 6)
                    } header: {
                        Text("Account")
                    } footer: {
                        Text("Use the same account in the web planner and the desktop app.")
                    }
                    Section { Button("Server…") { startEditingServer() } }
                }

                if let message {
                    Section { Text(message).font(.fsCaption).foregroundStyle(Theme.danger) }
                }
            }
            .fsScreen()
            .navigationTitle("Sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func startEditingServer() {
        url = sync.config?.url ?? ""
        anonKey = sync.config?.anonKey ?? ""
        editingServer = true
    }

    private func run(create: Bool) {
        busy = true
        message = nil
        Task {
            do { try await sync.signIn(email: email, password: password, createAccount: create) }
            catch { message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
            busy = false
        }
    }
}
