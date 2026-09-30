import SwiftUI
import UIKit

struct CardModifier: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardModifier(padding: padding)) }

    /// Standard dark screen background.
    func fsScreen() -> some View {
        background(Theme.background.ignoresSafeArea())
            .scrollContentBackground(.hidden)
    }
}

struct SectionHeader: View {
    var title: String
    var systemImage: String? = nil
    var action: (() -> Void)? = nil
    var actionLabel: String = "Add"

    var body: some View {
        HStack {
            if let systemImage {
                Image(systemName: systemImage).foregroundStyle(Theme.accent)
            }
            Text(title.uppercased())
                .font(.fsLabel)
                .tracking(1.2)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            if let action {
                Button(action: action) {
                    Label(actionLabel, systemImage: "plus")
                        .font(.fsLabel)
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderless)
                .tint(Theme.accent)
            }
        }
        .padding(.horizontal, 4)
    }
}

/// Large home-screen / toolbar tile, sized for thumbs.
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
                Image(systemName: systemImage)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(prominent ? Color.black : Theme.accent)
                Spacer(minLength: 0)
                Text(title.uppercased())
                    .font(.fsButton)
                    .foregroundStyle(prominent ? Color.black : Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(prominent ? Color.black.opacity(0.7) : Theme.textSecondary)
                        .lineLimit(2)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .background(prominent ? Theme.accent : Theme.surface,
                        in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            .opacity(disabled ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

/// Compact labelled figure ("CEILING 2.64 m").
struct StatView: View {
    var label: String
    var value: String
    var detail: String? = nil
    var highlight = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.fsLabel)
                .tracking(0.8)
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(.fsValue)
                .foregroundStyle(highlight ? Theme.accent : Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let detail {
                Text(detail).font(.caption2).foregroundStyle(Theme.textTertiary)
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
        let label = Text(text)
            .font(.system(size: 12, weight: .bold).width(.condensed))
            .tracking(0.6)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(selected ? Color.black : Theme.textSecondary)
            .background(selected ? Theme.accent : Theme.surfaceRaised, in: Capsule())
        if let action {
            Button(action: action) { label }.buttonStyle(.plain)
        } else {
            label
        }
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
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(filled ? Color.black : tint)
                    .frame(width: size, height: size)
                    .background(filled ? AnyShapeStyle(tint) : AnyShapeStyle(.ultraThinMaterial), in: Circle())
                if let label {
                    Text(label.uppercased())
                        .font(.system(size: 10, weight: .bold).width(.condensed))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                }
            }
        }
        .buttonStyle(.plain)
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
                .font(.title3)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(message).font(.subheadline).foregroundStyle(Theme.textSecondary)
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
                .font(.system(size: 36))
                .foregroundStyle(Theme.textTertiary)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
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
