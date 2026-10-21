import SwiftUI

/// The home screen's own look: the rest of the app keeps the original site style, but the
/// entry screen needs bigger targets and clearer tools. Poppins at readable weights (scaled
/// with Dynamic Type), a teal accent for things you can tap, rounded cards and more air.
enum HomeStyle {
    static let accent = Color(red: 0.30, green: 0.80, blue: 0.78)
    static let card = Color(red: 0.11, green: 0.11, blue: 0.118)
    static let cardRaised = Color(red: 0.17, green: 0.17, blue: 0.18)
    static let corner: CGFloat = 10
    static let sectionSpacing: CGFloat = 32
    static let minTap: CGFloat = 44

    static let section = Font.poppins(.semibold, 19, relativeTo: .title3)
    static let headline = Font.poppins(.medium, 16, relativeTo: .headline)
    static let body = Font.poppins(.regular, 16, relativeTo: .body)
    static let button = Font.poppins(.medium, 16, relativeTo: .body)
    static let footnote = Font.poppins(.regular, 13, relativeTo: .footnote)
}

extension View {
    func homeCard(padding: CGFloat = 14) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HomeStyle.card, in: RoundedRectangle(cornerRadius: HomeStyle.corner, style: .continuous))
    }
}

struct HomeSectionHeader: View {
    var title: String
    var action: (() -> Void)? = nil
    var actionLabel: String = "Add"

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(HomeStyle.section)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let action {
                Button(action: action) {
                    Label(actionLabel, systemImage: "plus")
                        .font(HomeStyle.button)
                        .foregroundStyle(HomeStyle.accent)
                        .frame(minHeight: HomeStyle.minTap)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.top, 4)
    }
}

/// Big, labelled entry point: icon, title and a one-line explanation. Disabled tiles stay
/// readable and say why they're unavailable.
struct HomeTile: View {
    var title: String
    var subtitle: String? = nil
    var systemImage: String
    var prominent = false
    var disabled = false
    var action: () -> Void

    var body: some View {
        let filled = prominent && !disabled
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: disabled ? "lock" : systemImage)
                    .font(.title2)
                    .foregroundStyle(filled ? Color.black : (disabled ? Theme.textTertiary : HomeStyle.accent))
                    .frame(height: 30)
                Text(title)
                    .font(HomeStyle.headline)
                    .foregroundStyle(filled ? Color.black : Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                if let subtitle {
                    Text(subtitle)
                        .font(HomeStyle.footnote)
                        .foregroundStyle(filled ? Color.black.opacity(0.7) : Theme.textTertiary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
            .background(filled ? HomeStyle.accent : HomeStyle.card,
                        in: RoundedRectangle(cornerRadius: HomeStyle.corner, style: .continuous))
            .opacity(disabled ? 0.6 : 1)
            .contentShape(RoundedRectangle(cornerRadius: HomeStyle.corner, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityHint(disabled ? (subtitle ?? "Unavailable on this device") : "")
    }
}

/// List row with an icon and a chevron.
struct HomeMenuRow: View {
    var title: String
    var subtitle: String? = nil
    var systemImage: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage).font(.title3).foregroundStyle(HomeStyle.accent).frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(HomeStyle.body).foregroundStyle(Theme.textPrimary)
                    if let subtitle {
                        Text(subtitle).font(HomeStyle.footnote).foregroundStyle(Theme.textTertiary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.textTertiary)
            }
            .frame(minHeight: HomeStyle.minTap)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
