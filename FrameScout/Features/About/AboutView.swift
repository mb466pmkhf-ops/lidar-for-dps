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
                    Text("Light readings, sizes, the sun's path and lens coverage are estimates for planning. Check them with a meter, a tape and the rental house before you rely on them.")
                        .font(.fsCaption)
                } header: {
                    Text("Estimates")
                }
                Section {
                    NavigationLink("Terms of use") { TermsView() }
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

/// The terms bundled with the app (`Resources/Terms.md`, also pasted into App Store Connect as
/// the licence agreement). A small reader for the headings, bullets and bold the file uses.
private struct TermsView: View {
    private var lines: [String] {
        guard let url = Bundle.main.url(forResource: "Terms", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return ["The terms of use could not be loaded. Contact us for a copy."]
        }
        return text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    if line.hasPrefix("# ") {
                        EmptyView() // the screen title says it
                    } else if line.hasPrefix("## ") {
                        Text(String(line.dropFirst(3))).font(.fsHeadline).padding(.top, 8)
                    } else if line.hasPrefix("- ") {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•")
                            Text(inline(String(line.dropFirst(2))))
                        }
                        .font(.fsCaption)
                    } else {
                        Text(inline(line)).font(.fsCaption)
                    }
                }
            }
            .textSelection(.enabled)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fsScreen()
        .navigationTitle("Terms of use")
        .navigationBarTitleDisplayMode(.inline)
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
