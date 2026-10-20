import SwiftUI
import UIKit

/// Visual language taken from norbertvarjasi.com: near-black page, white type, Poppins set
/// light with open tracking, a monospaced line for technical copy, square-cornered frames and
/// no decorative colour. White is the only "accent" — the image (or the scan) carries the colour.
/// The few functional colours (doors, windows, sun, warnings) are muted so they never shout.
enum Theme {
    static let background = Color(red: 0.027, green: 0.027, blue: 0.027)       // #070707
    static let surface = Color(red: 0.051, green: 0.051, blue: 0.051)          // #0D0D0D
    static let surfaceRaised = Color(red: 0.090, green: 0.090, blue: 0.090)    // #171717
    static let hairline = Color.white.opacity(0.12)

    static let accent = Color.white
    static let info = Color(red: 0.56, green: 0.65, blue: 0.74)
    static let success = Color(red: 0.62, green: 0.74, blue: 0.64)
    static let danger = Color(red: 0.86, green: 0.40, blue: 0.37)

    static let textPrimary = Color.white
    static let textSecondary = Color(white: 0.74)
    /// The grey of the site's icons and dividers (#69727D).
    static let textTertiary = Color(red: 0.41, green: 0.45, blue: 0.49)

    static let planWall = Color(white: 0.92)
    static let planDoor = Color(red: 0.62, green: 0.74, blue: 0.64)
    static let planWindow = Color(red: 0.56, green: 0.68, blue: 0.80)
    static let planObject = Color(white: 0.45)
    static let planFloor = Color(white: 1.0).opacity(0.04)
    static let sun = Color(red: 0.91, green: 0.78, blue: 0.52)

    /// Frames on the site are square; keep corners barely softened.
    static let corner: CGFloat = 2

    static let tracking: CGFloat = 0.9

    static func configureUIKitAppearance() {
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(background)
        nav.shadowColor = UIColor.white.withAlphaComponent(0.08)
        nav.titleTextAttributes = [.foregroundColor: UIColor.white,
                                   .font: UIFont.poppins(.regular, 15),
                                   .kern: 0.9]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor.white,
                                        .font: UIFont.poppins(.medium, 28),
                                        .kern: 0.4]
        let button = UIBarButtonItemAppearance()
        button.normal.titleTextAttributes = [.font: UIFont.poppins(.regular, 15), .kern: 0.6]
        nav.buttonAppearance = button
        nav.doneButtonAppearance = button
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().tintColor = .white

        UISegmentedControl.appearance().setTitleTextAttributes([.font: UIFont.poppins(.regular, 12)], for: .normal)
        UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(white: 0.22, alpha: 1)
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

    /// Small spaced label, like the site's navigation ("Selected Works").
    static let fsLabel = poppins(.regular, 11, relativeTo: .caption)
    static let fsButton = poppins(.regular, 14, relativeTo: .body)
    /// Large statement heading, like the site's "Director of Photography / London".
    static let fsTitle = poppins(.medium, 26, relativeTo: .title)
    static let fsHeadline = poppins(.regular, 16, relativeTo: .headline)
    static let fsBody = poppins(.light, 14, relativeTo: .subheadline)
    static let fsBodyStrong = poppins(.regular, 14, relativeTo: .subheadline)
    static let fsCaption = poppins(.light, 12, relativeTo: .caption)
    static let fsCaptionStrong = poppins(.medium, 12, relativeTo: .caption)
    static let fsMicro = poppins(.light, 10, relativeTo: .caption2)
    static let fsMicroStrong = poppins(.medium, 10, relativeTo: .caption2)
    /// Technical read-outs use a monospace, like the site's footer line.
    static let fsMono = Font.system(size: 12, weight: .regular, design: .monospaced)
    static let fsValue = Font.system(size: 20, weight: .light, design: .monospaced)
    static let fsBigValue = Font.system(size: 40, weight: .ultraLight, design: .monospaced)
}
