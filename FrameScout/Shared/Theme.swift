import SwiftUI
import UIKit

/// Practical field look: dark, high-contrast, iOS system type that follows the user's text
/// size, one warm accent for things you can tap, and rounded cards. Poppins stays bundled for
/// the PDF scout report only.
enum Theme {
    static let background = Color(red: 0.035, green: 0.035, blue: 0.04)
    static let surface = Color(red: 0.11, green: 0.11, blue: 0.118)            // iOS dark grouped cell
    static let surfaceRaised = Color(red: 0.17, green: 0.17, blue: 0.18)
    static let hairline = Color.white.opacity(0.14)

    /// Tappable things and the primary action. Warm amber reads well in daylight.
    static let accent = Color(red: 1.0, green: 0.78, blue: 0.30)
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

    static let corner: CGFloat = 12

    /// Letter spacing for labels. Zero: wide tracking hurts legibility at a glance.
    static let tracking: CGFloat = 0

    /// Minimum height for anything tappable in the field (Apple HIG: 44 pt).
    static let minTap: CGFloat = 44

    static func configureUIKitAppearance() {
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(background)
        nav.shadowColor = UIColor.white.withAlphaComponent(0.08)
        nav.titleTextAttributes = [.foregroundColor: UIColor.white]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
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

    // System text styles, so everything scales with the user's Dynamic Type setting.
    static let fsLabel = Font.footnote.weight(.semibold)
    static let fsButton = Font.body.weight(.semibold)
    static let fsTitle = Font.title2.weight(.bold)
    static let fsHeadline = Font.headline
    static let fsBody = Font.body
    static let fsBodyStrong = Font.body.weight(.semibold)
    static let fsCaption = Font.subheadline
    static let fsCaptionStrong = Font.subheadline.weight(.semibold)
    static let fsMicro = Font.caption
    static let fsMicroStrong = Font.caption.weight(.semibold)
    /// Numbers keep fixed-width digits so values don't jump while they update.
    static let fsMono = Font.subheadline.monospacedDigit()
    static let fsValue = Font.title2.weight(.semibold).monospacedDigit()
    static let fsBigValue = Font.largeTitle.weight(.bold).monospacedDigit()
}
