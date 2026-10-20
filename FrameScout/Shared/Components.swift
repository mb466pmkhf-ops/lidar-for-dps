import SwiftUI
import UIKit

struct CardModifier: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: Rectangle())
            .overlay(Rectangle().stroke(Theme.hairline, lineWidth: 0.5))
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardModifier(padding: padding)) }

    /// Standard dark screen background.
    func fsScreen() -> some View {
        background(Theme.background.ignoresSafeArea())
            .scrollContentBackground(.hidden)
    }

    /// The site's spaced small-caps-free label treatment.
    func fsTracked(_ amount: CGFloat = Theme.tracking) -> some View { tracking(amount) }
}

/// Lower-case wordmark in the spirit of the site's "norbert varjasi / cinematographer" lockup.
struct Wordmark: View {
    var subtitle: String = "location scouting · previs"

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("frame scout")
                .font(.poppins(.medium, 15))
                .tracking(2.2)
                .foregroundStyle(Theme.textSecondary)
            Text(subtitle)
                .font(.poppins(.light, 10))
                .tracking(1.8)
                .foregroundStyle(Theme.textTertiary)
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
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.fsLabel)
                .tracking(Theme.tracking)
                .foregroundStyle(Theme.textPrimary)
            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 0.5)
                .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] }
            if let action {
                Button(action: action) {
                    Text("+ \(actionLabel)")
                        .font(.fsLabel)
                        .tracking(Theme.tracking)
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 2)
        .padding(.top, 6)
    }
}

/// Home / toolbar entry. Square frame, hairline border, text first — no icon tiles.
struct ActionTile: View {
    var title: String
    var subtitle: String? = nil
    var systemImage: String
    var prominent = false
    var disabled = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Text(title)
                        .font(.poppins(.regular, 15))
                        .tracking(Theme.tracking)
                        .foregroundStyle(prominent ? Color.black : Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Spacer(minLength: 4)
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .ultraLight))
                        .foregroundStyle(prominent ? Color.black.opacity(0.7) : Theme.textTertiary)
                }
                Spacer(minLength: 0)
                if let subtitle {
                    Text(subtitle)
                        .font(.fsCaption)
                        .foregroundStyle(prominent ? Color.black.opacity(0.65) : Theme.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .background(prominent ? Color.white : Theme.surface, in: Rectangle())
            .overlay(Rectangle().stroke(prominent ? Color.clear : Theme.hairline, lineWidth: 0.5))
            .opacity(disabled ? 0.35 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

/// Text row with a hairline under it, like an entry in the site's work list.
struct MenuRow: View {
    var title: String
    var subtitle: String? = nil
    var trailing: String? = nil
    var disabled = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.poppins(.light, 21, relativeTo: .title3))
                        .tracking(0.6)
                        .foregroundStyle(Theme.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.fsCaption)
                            .tracking(0.4)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                Spacer()
                Text(trailing ?? "→")
                    .font(trailing == nil ? .poppins(.light, 16) : .fsMono)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
            .opacity(disabled ? 0.35 : 1)
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
                        .tracking(Theme.tracking)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.fsLabel)
                .tracking(Theme.tracking)
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(.fsValue)
                .foregroundStyle(highlight ? Theme.textPrimary : Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let detail {
                Text(detail).font(.fsMicro).foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TagChip: View {
    var text: String
    var selected = true
    var action: (() -> Void)? = nil

    var body: some View {
        let label = Text(text.capitalized)
            .font(.fsLabel)
            .tracking(Theme.tracking)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(selected ? Theme.textPrimary : Theme.textTertiary)
            .overlay(Rectangle().stroke(selected ? Color.white.opacity(0.7) : Theme.hairline, lineWidth: 0.5))
        if let action {
            Button(action: action) { label }.buttonStyle(.plain)
        } else {
            label
        }
    }
}

/// Square hairline button (secondary) or white block (primary) — replaces the system's
/// rounded bordered styles.
struct HairlineButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.fsLabel)
            .tracking(Theme.tracking)
            .labelStyle(.titleOnly)
            .foregroundStyle(prominent ? Color.black : Theme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(prominent ? Color.white : Color.clear, in: Rectangle())
            .overlay(Rectangle().stroke(prominent ? Color.clear : Color.white.opacity(0.45), lineWidth: 0.5))
            .opacity(configuration.isPressed ? 0.6 : (isEnabled ? 1 : 0.35))
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
                    .font(.system(size: size * 0.34, weight: .light))
                    .foregroundStyle(filled ? Color.black : tint)
                    .frame(width: size, height: size)
                    .background(filled ? AnyShapeStyle(tint) : AnyShapeStyle(Color.black.opacity(0.45)), in: Circle())
                    .overlay(Circle().stroke(filled ? Color.clear : Color.white.opacity(0.25), lineWidth: 0.5))
                if let label {
                    Text(label)
                        .font(.fsMicro)
                        .tracking(Theme.tracking)
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
            Text(provenance.label.uppercased()).font(.fsMicroStrong).tracking(Theme.tracking)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .foregroundStyle(provenance == .measured ? Theme.textSecondary : Theme.sun)
        .overlay(Rectangle().stroke(provenance == .measured ? Theme.hairline : Theme.sun.opacity(0.6),
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
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.fsHeadline).tracking(0.4)
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
                .font(.system(size: 28, weight: .ultraLight))
                .foregroundStyle(Theme.textTertiary)
            Text(title).font(.fsHeadline).tracking(0.4)
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
