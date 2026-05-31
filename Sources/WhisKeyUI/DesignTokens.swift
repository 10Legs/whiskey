import SwiftUI

// MARK: - Color convenience

extension Color {
    init(light: Color, dark: Color) {
        self.init(NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
            case .darkAqua: return NSColor(dark)
            default:        return NSColor(light)
            }
        })
    }
}

// MARK: - HalideTokens

/// Single source of truth for all visual constants in the Halide design system.
enum HalideTokens {

    // MARK: - Background

    /// Primary window/panel canvas background.
    static let backgroundPrimary = Color(
        light: Color(red: 245/255, green: 246/255, blue: 248/255),
        dark: Color(red: 18/255, green: 20/255, blue: 27/255)
    )

    /// Card and section background — slightly lighter than primary.
    static let backgroundSecondary = Color(
        light: Color(red: 235/255, green: 237/255, blue: 241/255),
        dark: Color(red: 27/255, green: 30/255, blue: 39/255)
    )

    // MARK: - Text

    /// Primary text — near-white in dark mode, near-black in light mode.
    static let textPrimary = Color(
        light: Color(red: 18/255, green: 20/255, blue: 27/255),
        dark: Color(red: 242/255, green: 243/255, blue: 247/255)
    )

    /// Secondary text — 55% opacity of primary.
    static let textSecondary = textPrimary.opacity(0.55)

    /// Tertiary text — 30% opacity of primary. Used for section headers.
    static let textTertiary  = textPrimary.opacity(0.30)

    // MARK: - Border

    /// Subtle border — 7% white in dark mode, 8% black in light mode.
    static let borderSubtle  = Color(light: Color.black.opacity(0.08), dark: Color.white.opacity(0.07))

    /// Default border — 12% white in dark mode, 14% black in light mode.
    static let borderDefault = Color(light: Color.black.opacity(0.14), dark: Color.white.opacity(0.12))

    // MARK: - Accent (fixed, non-adaptive)

    /// Primary interactive accent — tungsten amber rgb(242,163,38).
    static let accentAmber       = Color(red: 242/255, green: 163/255, blue: 38/255)

    /// Dim accent fill for button backgrounds.
    static let accentAmberDim    = accentAmber.opacity(0.20)

    /// Accent border at rest opacity.
    static let accentAmberBorder = accentAmber.opacity(0.45)

    /// Recording state color — same as accentAmber but named for semantic clarity.
    static let accentRecording   = accentAmber

    /// Idle waveform line color — cool slate rgb(130,168,185).
    static let accentIdle        = Color(red: 130/255, green: 168/255, blue: 185/255)

    /// Destructive action color — always system red.
    static let accentDestructive = Color(nsColor: .systemRed)

    // MARK: - Typography

    /// Caption text — 11pt rounded regular. Used for HUD caption strip and status labels.
    static let fontCaption = Font.system(size: 11, weight: .regular, design: .rounded)

    // MARK: - Corner radius scale

    static let radiusSmall: CGFloat = 6
    static let radiusMedium: CGFloat = 10
    static let radiusLarge: CGFloat = 14
    static let radiusXL: CGFloat = 16

    // MARK: - Spacing scale

    static let spacing2: CGFloat = 2
    static let spacing4: CGFloat = 4
    static let spacing6: CGFloat = 6
    static let spacing8: CGFloat = 8
    static let spacing12: CGFloat = 12
    static let spacing16: CGFloat = 16
    static let spacing20: CGFloat = 20
    static let spacing24: CGFloat = 24

    // MARK: - Shadow

    /// Standard HUD panel shadow.
    static let hudShadowColor = Color.black
    static let hudShadowOpacity = 0.40
    static let hudShadowRadius: CGFloat = 24
    static let hudShadowY: CGFloat = 4

    /// Card shadow for settings sections.
    static let cardShadowColor = Color.black
    static let cardShadowOpacity = 0.20
    static let cardShadowRadius: CGFloat = 8
    static let cardShadowY: CGFloat = 2
}
