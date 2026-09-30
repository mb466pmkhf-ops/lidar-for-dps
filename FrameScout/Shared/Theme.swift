import SwiftUI
import UIKit

/// Dark, high-contrast palette. Amber is the "frame line" colour used for anything actionable
/// or optical; everything else stays neutral so it reads on set in bright or dark conditions.
enum Theme {
    static let background = Color(red: 0.047, green: 0.047, blue: 0.055)
    static let surface = Color(red: 0.105, green: 0.105, blue: 0.118)
    static let surfaceRaised = Color(red: 0.16, green: 0.16, blue: 0.176)
    static let hairline = Color.white.opacity(0.08)

    static let accent = Color(red: 1.0, green: 0.74, blue: 0.18)
    static let info = Color(red: 0.38, green: 0.72, blue: 1.0)
    static let success = Color(red: 0.36, green: 0.84, blue: 0.52)
    static let danger = Color(red: 1.0, green: 0.36, blue: 0.32)

    static let textPrimary = Color.white
    static let textSecondary = Color(white: 0.62)
    static let textTertiary = Color(white: 0.42)

    static let planWall = Color(white: 0.92)
    static let planDoor = Color(red: 0.36, green: 0.84, blue: 0.52)
    static let planWindow = Color(red: 0.38, green: 0.72, blue: 1.0)
    static let planObject = Color(white: 0.5)
    static let planFloor = Color(white: 1.0).opacity(0.05)
    static let sun = Color(red: 1.0, green: 0.82, blue: 0.3)

    static let corner: CGFloat = 14

    static func configureUIKitAppearance() {
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(background)
        nav.shadowColor = .clear
        nav.titleTextAttributes = [.foregroundColor: UIColor.white]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor.white,
                                        .font: UIFont.systemFont(ofSize: 30, weight: .heavy)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
    }
}

extension Font {
    /// Condensed, uppercase-friendly label style used for section headers and big buttons.
    static let fsLabel = Font.system(size: 13, weight: .bold, design: .default).width(.condensed)
    static let fsButton = Font.system(size: 17, weight: .heavy, design: .default).width(.condensed)
    static let fsValue = Font.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit()
    static let fsBigValue = Font.system(size: 44, weight: .bold, design: .rounded).monospacedDigit()
}
