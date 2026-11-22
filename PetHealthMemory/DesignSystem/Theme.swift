import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Cross-platform (iOS + macOS) design tokens — DESIGN.md palette, revised per docs/DESIGN_REVIEW.md.
///
/// Rule of thumb:
/// - `status*` / `brand*` are **fills, icons and large shapes**.
/// - `*Text` variants are the only colours allowed for **text** on `bgCanvas` / `bgSurface`
///   (all ≥ 4.5:1 in light mode; dark mode reuses the fill colour which already passes).
enum AppTheme {
    enum Colors {
        // Brand — light primary deepened from #4E8C7D (3.9:1) to #3F7568 (5.3:1 white-on-primary).
        static let brandPrimary = Color.adaptive(light: 0x3F7568, dark: 0x6DB3A2)
        static let brandPrimarySoft = Color.adaptive(light: 0xE7F2EF, dark: 0x1F332E)
        static let brandAccent = Color.adaptive(light: 0xE09A6C, dark: 0xE8A87C)
        /// Label colour placed on top of `brandPrimary` fills.
        static let onBrandPrimary = Color.adaptive(light: 0xFFFFFF, dark: 0x0F1A17)

        // Surfaces
        static let bgCanvas = Color.adaptive(light: 0xF8F7F4, dark: 0x121413)
        static let bgSurface = Color.adaptive(light: 0xFFFFFF, dark: 0x1C1F1E)
        static let bgElevated = Color.adaptive(light: 0xF1EFEA, dark: 0x262A28)

        // Text
        static let textPrimary = Color.adaptive(light: 0x1E2422, dark: 0xF2F4F3)
        static let textSecondary = Color.adaptive(light: 0x5C6763, dark: 0x9AA6A2)
        static let borderSubtle = Color.adaptive(light: 0xE6E3DC, dark: 0x2E3331)

        // Status fills (icons, strokes, tinted backgrounds)
        static let statusSuccess = Color.adaptive(light: 0x3D9970, dark: 0x52B788)
        static let statusWarning = Color.adaptive(light: 0xD99B26, dark: 0xE6B34B)
        static let statusDanger = Color.adaptive(light: 0xD65A5A, dark: 0xE57373)
        static let statusSource = Color.adaptive(light: 0x5A84A2, dark: 0x7AA6C4)

        // Status text (WCAG AA ≥ 4.5:1 on canvas & surface)
        static let successText = Color.adaptive(light: 0x2E7D5B, dark: 0x52B788)
        static let warningText = Color.adaptive(light: 0x8A5F0C, dark: 0xE6B34B)
        static let dangerText = Color.adaptive(light: 0xB04545, dark: 0xE57373)
        static let sourceText = Color.adaptive(light: 0x466C8C, dark: 0x7AA6C4)
        static let brandText = Color.adaptive(light: 0x3F7568, dark: 0x6DB3A2)
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
    }

    /// macOS uses tighter radii and control heights: it's a pointer UI, not a touch UI.
    enum Radius {
        #if os(macOS)
        static let chip: CGFloat = 6
        static let input: CGFloat = 8
        static let card: CGFloat = 10
        static let sheet: CGFloat = 12
        #else
        static let chip: CGFloat = 10
        static let input: CGFloat = 12
        static let card: CGFloat = 16
        static let sheet: CGFloat = 20
        #endif
    }

    enum Size {
        static let minTouch: CGFloat = 44
        /// Height of primary/secondary buttons.
        #if os(macOS)
        static let button: CGFloat = 32
        #else
        static let button: CGFloat = 50
        #endif
        static let rowIcon: CGFloat = 36
        static let thumbnail: CGFloat = 56
    }

    /// Motion tokens. Always resolve through `Motion.animation(_:reduceMotion:)` in views
    /// so Reduce Motion falls back to an opacity-only fade.
    enum Motion {
        /// Default spring for layout changes (DESIGN.md).
        static let standard = Animation.spring(duration: 0.35, bounce: 0.15)
        /// Filter / pet switch content crossfade.
        static let quick = Animation.easeInOut(duration: 0.2)
        /// Completion feedback (checkmarks, confirm collapse) — slightly snappier, no extra bounce.
        static let confirm = Animation.spring(duration: 0.3, bounce: 0.1)
        /// Reduce Motion replacement.
        static let reduced = Animation.easeInOut(duration: 0.15)

        static func animation(_ base: Animation, reduceMotion: Bool) -> Animation {
            reduceMotion ? reduced : base
        }
    }
}

extension Color {
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        #if canImport(UIKit)
        return Color(
            uiColor: UIColor { trait in
                let hex = trait.userInterfaceStyle == .dark ? dark : light
                return UIColor(
                    red: CGFloat((hex >> 16) & 0xFF) / 255.0,
                    green: CGFloat((hex >> 8) & 0xFF) / 255.0,
                    blue: CGFloat(hex & 0xFF) / 255.0,
                    alpha: 1.0
                )
            }
        )
        #elseif canImport(AppKit)
        return Color(
            nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                let hex = isDark ? dark : light
                return NSColor(
                    srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
                    green: CGFloat((hex >> 8) & 0xFF) / 255.0,
                    blue: CGFloat(hex & 0xFF) / 255.0,
                    alpha: 1.0
                )
            }
        )
        #endif
    }
}
