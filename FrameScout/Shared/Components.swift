import SwiftUI
import UIKit

struct CardModifier: ViewModifier {
    var padding: CGFloat = 18
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
    }
}

extension View {
    func card(padding: CGFloat = 18) -> some View { modifier(CardModifier(padding: padding)) }

    /// Standard dark screen background.
    func fsScreen() -> some View {
        background(Theme.background.ignoresSafeArea())
            .scrollContentBackground(.hidden)
    }

    func fsTracked(_ amount: CGFloat = Theme.tracking) -> some View { tracking(amount) }
}

struct Wordmark: View {
    var subtitle: String = "Location scouting"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("FrameScout").font(.fsHeadline)
            Text(subtitle).font(.fsMicro).foregroundStyle(Theme.textTertiary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct SectionHeader: View {
    var title: String
    var systemImage: String? = nil
    var action: (() -> Void)? = nil
    var actionLabel: String = "Add"

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.fsSection)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let action {
                Button(action: action) {
                    Label(actionLabel, systemImage: "plus")
                        .font(.fsButton)
                        .foregroundStyle(Theme.accent)
                        .frame(minHeight: Theme.minTap)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.top, 4)
    }
}

/// Big, labelled entry point: icon, title and a one-line explanation. Disabled tiles stay
/// readable and say why they're unavailable.
struct ActionTile: View {
    var title: String
    var subtitle: String? = nil
    var systemImage: String
    var prominent = false
    var disabled = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: disabled ? "lock" : systemImage)
                    .font(.title2)
                    .foregroundStyle(prominent && !disabled ? Color.black : (disabled ? Theme.textTertiary : Theme.accent))
                    .frame(height: 30)
                Text(title)
                    .font(.fsHeadline)
                    .foregroundStyle(prominent && !disabled ? Color.black : Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                if let subtitle {
                    Text(subtitle)
                        .font(.fsFootnote)
                        .foregroundStyle(prominent && !disabled ? Color.black.opacity(0.7) : Theme.textTertiary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
            .background(prominent && !disabled ? Theme.accent : Theme.surface,
                        in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            .opacity(disabled ? 0.6 : 1)
            .contentShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityHint(disabled ? (subtitle ?? "Unavailable on this device") : "")
    }
}

/// List-style row with an optional icon and a chevron.
struct MenuRow: View {
    var title: String
    var subtitle: String? = nil
    var trailing: String? = nil
    var systemImage: String? = nil
    var disabled = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let systemImage {
                    Image(systemName: systemImage).font(.title3).foregroundStyle(Theme.accent).frame(width: 30)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.fsBody).foregroundStyle(Theme.textPrimary)
                    if let subtitle {
                        Text(subtitle).font(.fsFootnote).foregroundStyle(Theme.textTertiary)
                    }
                }
                Spacer()
                if let trailing { Text(trailing).font(.fsMono).foregroundStyle(Theme.textTertiary) }
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.textTertiary)
            }
            .frame(minHeight: Theme.minTap)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .opacity(disabled ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

/// Text tabs with a thin underline on the active one — the site's navigation bar.
struct UnderlineTabs<Value: Hashable>: View {
    var options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 18) {
            ForEach(options.indices, id: \.self) { i in
                let value = options[i].0
                let label = options[i].1
                let active = value == selection
                Button { selection = value } label: {
                    Text(label)
                        .font(.fsLabel)
                        .foregroundStyle(active ? Color.white : Color.white.opacity(0.55))
                        .padding(.vertical, 6)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Color.white).frame(height: 1).opacity(active ? 1 : 0)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Compact labelled figure ("Ceiling  2.64 m").
struct StatView: View {
    var label: String
    var value: String
    var detail: String? = nil
    var highlight = false
    var provenance: Provenance? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.fsLabel)
                .tracking(Theme.tracking)
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.fsValue)
                .foregroundStyle(highlight ? Theme.textPrimary : Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let detail {
                Text(detail).font(.fsMicro).foregroundStyle(Theme.textTertiary)
            }
            if let provenance, value != "—" { ProvenanceBadge(provenance: provenance) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct TagChip: View {
    var text: String
    var selected = true
    var action: (() -> Void)? = nil

    var body: some View {
        let label = Text(text.capitalized)
            .font(.fsLabel)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .foregroundStyle(selected ? Color.black : Theme.textSecondary)
            .background(selected ? Theme.accent : Theme.surfaceRaised, in: Capsule())
        if let action {
            Button(action: action) { label }.buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
        } else {
            label
        }
    }
}

/// Rounded button: accent fill for the primary action, outlined otherwise. At least 44 pt tall.
struct HairlineButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.fsButton)
            .foregroundStyle(prominent ? Color.black : Theme.accent)
            .padding(.horizontal, 16)
            .frame(minHeight: Theme.minTap)
            .background(prominent ? Theme.accent : Theme.surfaceRaised,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : (isEnabled ? 1 : 0.4))
    }
}

/// Simple wrapping layout for tag chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Round translucent control for use over camera / AR views.
struct OverlayButton: View {
    var systemImage: String
    var label: String? = nil
    var tint: Color = .white
    var filled = false
    var size: CGFloat = 56
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(filled ? Color.black : tint)
                    .frame(width: size, height: size)
                    .background(filled ? AnyShapeStyle(tint) : AnyShapeStyle(Color.black.opacity(0.45)), in: Circle())
                    .overlay(Circle().stroke(filled ? Color.clear : Color.white.opacity(0.25), lineWidth: 0.5))
                if let label {
                    Text(label)
                        .font(.fsMicro)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.8), radius: 2)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// Says whether a figure was measured, estimated or entered by hand. Shape and word carry the
/// meaning (not colour alone), so it reads in sunlight, in grayscale and with VoiceOver.
struct ProvenanceBadge: View {
    var provenance: Provenance

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: provenance.symbol).font(.system(size: 9, weight: .regular))
            Text(provenance.label.uppercased()).font(.fsMicroStrong)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .foregroundStyle(provenance == .measured ? Theme.textSecondary : Theme.estimate)
        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(provenance == .measured ? Theme.hairline : Theme.estimate.opacity(0.6),
                                    style: StrokeStyle(lineWidth: 0.5, dash: provenance == .estimated ? [2, 2] : [])))
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(provenance.label) value")
        .accessibilityHint(provenance.explanation)
    }
}

/// A labelled figure with its provenance badge, for Forms and Lists.
struct ProvenanceFigureRow: View {
    var label: String
    var value: String
    var provenance: Provenance?

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                Text(value)
                if let provenance, value != "—" { ProvenanceBadge(provenance: provenance) }
            }
        } label: {
            Text(label)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One-line key to the badges, shown under lists of figures.
struct ProvenanceLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Provenance.allCases) { p in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    ProvenanceBadge(provenance: p).accessibilityHidden(true)
                    Text(p.explanation).font(.fsMicro).foregroundStyle(Theme.textTertiary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(p.label): \(p.explanation)")
            }
        }
    }
}

/// Explains a hardware limitation instead of silently hiding a feature.
struct RequirementBanner: View {
    var title: String
    var message: String
    var systemImage: String = "exclamationmark.triangle"

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Theme.textTertiary)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.fsHeadline)
                Text(message).font(.fsBody).foregroundStyle(Theme.textSecondary)
            }
        }
        .card()
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Identifiable wrapper so a URL can drive `.sheet(item:)`.
struct SharedFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct EmptyStateView: View {
    var systemImage: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(Theme.textTertiary)
            Text(title).font(.fsHeadline)
            Text(message)
                .font(.fsBody)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

extension UIImage {
    /// Aspect-preserving downsample (longest side = `maxPixel` points).
    func downsampled(maxPixel: CGFloat) -> UIImage? {
        let longest = max(size.width, size.height)
        guard longest > maxPixel, longest > 0 else { return self }
        let scale = maxPixel / longest
        return preparingThumbnail(of: CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded()))
    }
}
