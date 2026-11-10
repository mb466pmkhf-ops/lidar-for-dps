import SwiftUI
import UIKit

/// "Big buttons, daylight" (Docs/DECISIONS.md D-008): a light screen that reads in the sun, large
/// rounded controls and one blue accent. Every colour has a night partner: a dim, near-black screen
/// with a soft red accent, so the phone puts as little light as possible into a dark set. SwiftUI
/// picks the partner from the colour scheme, which the app sets from the Night switch
/// (`Theme.nightKey`). Capture screens over the camera always use the night set.
enum Theme {
    /// UserDefaults key of the Night switch.
    static let nightKey = "appearance.night"

    static func ui(_ day: UIColor, _ night: UIColor) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? night : day }
    }
    static func pair(_ day: UIColor, _ night: UIColor) -> Color { Color(ui(day, night)) }
    private static func hex(_ v: UInt32, _ alpha: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: alpha)
    }

    static let uiBackground = ui(hex(0xF3F4F1), hex(0x000000))
    static let uiText = ui(hex(0x14181A), hex(0xB9B2AE))
    static let uiAccent = ui(hex(0x1F5FD1), hex(0xB5483F))

    static let background = Color(uiBackground)
    static let surface = pair(hex(0xFFFFFF), hex(0x0A0A0A))
    static let surfaceRaised = pair(hex(0xE9EEF6), hex(0x171717))
    static let hairline = pair(hex(0xD9DDD8), UIColor(white: 1, alpha: 0.12))
    static let hairlineStrong = pair(hex(0xAEB6B0), UIColor(white: 1, alpha: 0.3))

    static let accent = Color(uiAccent)
    /// Text and icons on top of an accent fill.
    static let onAccent = pair(.white, .black)
    static let info = pair(hex(0x4A6FA5), hex(0x6F8196))
    static let success = pair(hex(0x1E7A45), hex(0x5D8A66))
    static let danger = pair(hex(0xB3261E), hex(0xC2554D))

    static let textPrimary = Color(uiText)
    static let textSecondary = pair(hex(0x4F5958), hex(0x8F8884))
    static let textTertiary = pair(hex(0x5F6968), hex(0x7D7672))
    /// Translucent backing for chips and hints that sit on the plan.
    static let overlay = pair(UIColor(white: 1, alpha: 0.92), UIColor(white: 0, alpha: 0.65))

    /// The plan drawing: ink on paper by day, dim lines on black at night.
    static let ink = Color(uiText)
    static let planWall = pair(hex(0x14181A), hex(0x9A938F))
    static let planDoor = pair(hex(0x4E8A5F), hex(0x4F7A58))
    static let planWindow = pair(hex(0x5B8DE0), hex(0x4F6A85))
    static let planObject = pair(hex(0x8A9391), hex(0x5C5652))
    static let planFloor = pair(UIColor(white: 0, alpha: 0.04), UIColor(white: 1, alpha: 0.04))
    static let planGrid = pair(UIColor(white: 0, alpha: 0.06), UIColor(white: 1, alpha: 0.05))
    static let planEquipment = pair(hex(0x14181A), hex(0x8F8884))
    static let planStand = pair(hex(0x8A9391), hex(0x5C5652))
    static let sun = pair(hex(0xB36B00), UIColor(red: 0.91, green: 0.78, blue: 0.52, alpha: 1))

    /// Rounded, finger-sized controls.
    static let corner: CGFloat = 12

    static let tracking: CGFloat = 0.2

    static func configureUIKitAppearance() {
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = uiBackground
        nav.shadowColor = ui(UIColor(white: 0, alpha: 0.1), UIColor(white: 1, alpha: 0.08))
        nav.titleTextAttributes = [.foregroundColor: uiText,
                                   .font: UIFont.poppins(.medium, 16)]
        nav.largeTitleTextAttributes = [.foregroundColor: uiText,
                                        .font: UIFont.poppins(.semibold, 28)]
        let button = UIBarButtonItemAppearance()
        button.normal.titleTextAttributes = [.font: UIFont.poppins(.medium, 16)]
        nav.buttonAppearance = button
        nav.doneButtonAppearance = button
        UINavigationBar.appearance().standardAppearance = nav
        // On iOS 26 a scroll-edge appearance set through the proxy hides SwiftUI large titles;
        // leaving it unset lets the system derive it from the standard appearance.
        if #unavailable(iOS 26) {
            UINavigationBar.appearance().scrollEdgeAppearance = nav
        }
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().tintColor = uiAccent

        UISegmentedControl.appearance().setTitleTextAttributes([.font: UIFont.poppins(.medium, 13), .foregroundColor: uiText], for: .normal)
        UISegmentedControl.appearance().setTitleTextAttributes([.font: UIFont.poppins(.medium, 13), .foregroundColor: ui(.white, .black)], for: .selected)
        UISegmentedControl.appearance().selectedSegmentTintColor = uiAccent
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
    static let fsLabel = poppins(.medium, 12, relativeTo: .caption)
    static let fsButton = poppins(.medium, 15, relativeTo: .body)
    /// Large statement heading, like the site's "Director of Photography / London".
    static let fsTitle = poppins(.semibold, 26, relativeTo: .title)
    static let fsHeadline = poppins(.medium, 17, relativeTo: .headline)
    static let fsBody = poppins(.regular, 15, relativeTo: .subheadline)
    static let fsBodyStrong = poppins(.medium, 15, relativeTo: .subheadline)
    static let fsCaption = poppins(.regular, 13, relativeTo: .caption)
    static let fsCaptionStrong = poppins(.medium, 13, relativeTo: .caption)
    static let fsMicro = poppins(.regular, 11, relativeTo: .caption2)
    static let fsMicroStrong = poppins(.medium, 11, relativeTo: .caption2)
    /// Technical read-outs use a monospace, like the site's footer line.
    static let fsMono = Font.system(size: 12, weight: .regular, design: .monospaced)
    static let fsValue = Font.system(size: 20, weight: .medium, design: .monospaced)
    static let fsBigValue = Font.system(size: 40, weight: .light, design: .monospaced)
}
