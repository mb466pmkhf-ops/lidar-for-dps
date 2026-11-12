import SwiftUI

/// The home screen's own look: the rest of the app keeps the original site style, but the
/// entry screen needs bigger targets and clearer tools. Poppins at readable weights (scaled
/// with Dynamic Type), a teal accent for things you can tap, rounded cards and more air.
enum HomeStyle {
    static let accent = Theme.accent
    static let card = Theme.surface
    static let cardRaised = Theme.surfaceRaised
    static let corner: CGFloat = Theme.corner
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
            .overlay(RoundedRectangle(cornerRadius: HomeStyle.corner, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
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

/// The one filled button on Home (Scan a location). Same shape as every other button in the app.
struct HomePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Theme.onAccent)
            .background(HomeStyle.accent, in: RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// Home's rows are the app-wide `ListRow`.
typealias HomeMenuRow = ListRow
