import SwiftUI
import UIKit

/// Field-friendly but with the original character: dark, high-contrast, Poppins at readable
/// weights that follows the user's text size, monospaced read-outs for figures, one cool accent
/// for things you can tap, softly rounded cards and generous spacing between sections.
enum Theme {
    static let background = Color(red: 0.035, green: 0.035, blue: 0.04)
    static let surface = Color(red: 0.11, green: 0.11, blue: 0.118)            // iOS dark grouped cell
    static let surfaceRaised = Color(red: 0.17, green: 0.17, blue: 0.18)
    static let hairline = Color.white.opacity(0.14)

    /// Tappable things and the primary action. A cool teal that stays clear of the functional
    /// colours (windows blue, doors green, warnings red, sun warm) and keeps black text legible.
    static let accent = Color(red: 0.30, green: 0.80, blue: 0.78)
    /// Estimated and manual figures, so a guess never looks like a measurement.
    static let estimate = Color(red: 1.0, green: 0.64, blue: 0.40)
    static let info = Color(red: 0.45, green: 0.68, blue: 0.95)
    static let success = Color(red: 0.42, green: 0.82, blue: 0.52)
    static let danger = Color(red: 0.98, green: 0.42, blue: 0.38)

    static let textPrimary = Color.white
    static let textSecondary = Color(white: 0.80)
    static let textTertiary = Color(white: 0.60)

    static let planWall = Color(white: 0.92)
    static let planDoor = Color(red: 0.42, green: 0.82, blue: 0.52)
    static let planWindow = Color(red: 0.45, green: 0.68, blue: 0.95)
    static let planObject = Color(white: 0.5)
    static let planFloor = Color(white: 1.0).opacity(0.05)
    static let sun = Color(red: 1.0, green: 0.80, blue: 0.35)

    static let corner: CGFloat = 10

    /// Letter spacing for small uppercase labels only; body text stays untracked.
    static let tracking: CGFloat = 0.8

    /// Vertical space between sections of a screen, and between items inside one.
    static let sectionSpacing: CGFloat = 32
    static let itemSpacing: CGFloat = 14

    /// Minimum height for anything tappable in the field (Apple HIG: 44 pt).
    static let minTap: CGFloat = 44

    static func configureUIKitAppearance() {
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(background)
        nav.shadowColor = UIColor.white.withAlphaComponent(0.08)
        nav.titleTextAttributes = [.foregroundColor: UIColor.white,
                                   .font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: .poppins(.medium, 17))]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor.white,
                                        .font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: .poppins(.semibold, 32))]
        let button = UIBarButtonItemAppearance()
        button.normal.titleTextAttributes = [.font: UIFontMetrics(forTextStyle: .body).scaledFont(for: .poppins(.regular, 17))]
        nav.buttonAppearance = button
        nav.doneButtonAppearance = button
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().tintColor = UIColor(accent)
        UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(white: 0.3, alpha: 1)
    }
}

enum PoppinsWeight: String {
    case light = "Poppins-Light"
    case regular = "Poppins-Regular"
    case medium = "Poppins-Medium"
    case semibold = "Poppins-SemiBold"
}

extension UIFont {
    static func poppins(_ weight: PoppinsWeight, _ size: CGFloat) -> UIFont {
        UIFont(name: weight.rawValue, size: size) ?? .systemFont(ofSize: size)
    }
}

extension Font {
    static func poppins(_ weight: PoppinsWeight, _ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(weight.rawValue, size: size, relativeTo: style)
    }

    // Poppins sized to the matching iOS text style and scaled with it (Dynamic Type). Poppins
    // runs wide, so sizes sit a point under the system ones. No Light weight for running text.
    static let fsLabel = poppins(.medium, 12, relativeTo: .footnote)
    static let fsButton = poppins(.medium, 16, relativeTo: .body)
    static let fsTitle = poppins(.semibold, 24, relativeTo: .title2)
    static let fsSection = poppins(.semibold, 19, relativeTo: .title3)
    static let fsHeadline = poppins(.medium, 16, relativeTo: .headline)
    static let fsBody = poppins(.regular, 16, relativeTo: .body)
    static let fsBodyStrong = poppins(.medium, 16, relativeTo: .body)
    static let fsCaption = poppins(.regular, 14, relativeTo: .subheadline)
    static let fsCaptionStrong = poppins(.medium, 14, relativeTo: .subheadline)
    static let fsFootnote = poppins(.regular, 13, relativeTo: .footnote)
    static let fsMicro = poppins(.regular, 12, relativeTo: .caption)
    static let fsMicroStrong = poppins(.medium, 12, relativeTo: .caption)
    /// Figures use a monospace, as on the original site, so values line up and don't jump.
    static let fsMono = Font.system(.subheadline, design: .monospaced)
    static let fsValue = Font.system(.title2, design: .monospaced)
    static let fsBigValue = Font.system(.largeTitle, design: .monospaced).weight(.light)
}
