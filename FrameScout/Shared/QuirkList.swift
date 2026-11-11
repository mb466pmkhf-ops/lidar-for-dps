import SwiftUI

/// "Things to know" about a fixture type or recording format (`KnownQuirks`), collapsed by default
/// so the form stays short. Each line shows where it came from.
struct QuirkList: View {
    let quirks: [UnitQuirk]
    @State private var expanded = false

    var body: some View {
        if !quirks.isEmpty {
            DisclosureGroup(isExpanded: $expanded) {
                ForEach(quirks, id: \.self) { q in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(q.text).font(.fsCaption).foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let link = q.url.flatMap(URL.init(string:)) {
                            Link(destination: link) {
                                Text("Source: \(q.source)").font(.fsMicro)
                            }
                        } else {
                            Text("Source: \(q.source)").font(.fsMicro).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } label: {
                Label("Things to know (\(quirks.count))", systemImage: "info.circle")
                    .font(.fsBody)
                    .foregroundStyle(Theme.textPrimary)
            }
        }
    }
}
