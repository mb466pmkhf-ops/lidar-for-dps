import SwiftUI

/// Version, copyright, privacy summary and the open-source notices the app must ship
/// (the Poppins font is the only third-party code or asset in the iPhone app).
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "–"
        let b = info?["CFBundleVersion"] as? String ?? "–"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Version", value: version)
                    Text("© 2026 FrameScout. All rights reserved.")
                        .font(.fsCaption).foregroundStyle(Theme.textSecondary)
                }
                Section {
                    Text("Scans, meshes and photos stay on this iPhone. If you sign in to sync, your email, the projects and their 2D plans (including each location's address and GPS position) are stored on the sync server so your other devices can open them. No tracking, ads or analytics. You can delete your account and its synced projects under Account & sync.")
                        .font(.fsCaption)
                } header: {
                    Text("Privacy")
                }
                Section {
                    NavigationLink("Open-source notices") { NoticesView() }
                }
            }
            .fsScreen()
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private struct NoticesView: View {
    private var poppinsLicence: String {
        guard let url = Bundle.main.url(forResource: "OFL", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "Poppins is licensed under the SIL Open Font License, Version 1.1."
        }
        return text
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Poppins font").font(.fsHeadline)
                Text(poppinsLicence)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            .padding()
        }
        .fsScreen()
        .navigationTitle("Open-source notices")
        .navigationBarTitleDisplayMode(.inline)
    }
}
