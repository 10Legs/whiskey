// swiftlint:disable todo
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
/// Phase 1: aliases point to current phosphor values so there is zero visual delta.
/// Phase 2 will replace the aliases with real Halide values.
enum HalideTokens {

    // MARK: - Background (Phase 1: phosphor values; Phase 2: real graphite)

    // TODO: Halide Phase 2 — replace with Color(light: ..., dark: Color(red: 18/255, green: 20/255, blue: 27/255))
    /// Primary window/panel canvas background.
    static let backgroundPrimary = Color(red: 6/255, green: 8/255, blue: 8/255)

    // TODO: Halide Phase 2 — replace with Color(light: ..., dark: Color(red: 27/255, green: 30/255, blue: 39/255))
    /// Card and section background — slightly lighter than primary.
    static let backgroundSecondary = Color(red: 6/255, green: 8/255, blue: 8/255)

    // MARK: - Text

    // TODO: Halide Phase 2 — Color(light: Color(red:18/255,green:20/255,blue:27/255), dark: Color(red:242/255,green:243/255,blue:247/255))
    /// Primary text — near-white in dark mode, near-black in light mode.
    static let textPrimary = Color(red: 0, green: 1, blue: 0.533)

    // TODO: Halide Phase 2 — textPrimary.opacity(0.55)
    /// Secondary text — 55% opacity of primary.
    static let textSecondary = Color(red: 0, green: 1, blue: 0.533).opacity(0.55)

    // TODO: Halide Phase 2 — textPrimary.opacity(0.30)
    /// Tertiary text — 30% opacity of primary. Used for section headers.
    static let textTertiary = Color(red: 0, green: 1, blue: 0.533).opacity(0.30)

    // MARK: - Border

    // TODO: Halide Phase 2 — Color(light: Color.black.opacity(0.08), dark: Color.white.opacity(0.07))
    /// Subtle border — 7% white in dark mode.
    static let borderSubtle = Color(red: 0, green: 1, blue: 0.533).opacity(0.08)

    // TODO: Halide Phase 2 — Color(light: Color.black.opacity(0.14), dark: Color.white.opacity(0.12))
    /// Default border — 12% white in dark mode.
    static let borderDefault = Color(red: 0, green: 1, blue: 0.533).opacity(0.25)

    // MARK: - Accent (Phase 1: phosphor green; Phase 2: tungsten amber HSL 38 90% 58%)

    // TODO: Halide Phase 2 — Color(red: 242/255, green: 163/255, blue: 38/255)
    /// Primary interactive accent. Phase 2: rgb(242,163,38).
    static let accentAmber = Color(red: 0, green: 1, blue: 0.533)

    // TODO: Halide Phase 2 — accentAmber.opacity(0.20)
    /// Dim accent fill for button backgrounds.
    static let accentAmberDim = Color(red: 0, green: 1, blue: 0.533).opacity(0.15)

    // TODO: Halide Phase 2 — accentAmber.opacity(0.45)
    /// Accent border at rest opacity.
    static let accentAmberBorder = Color(red: 0, green: 1, blue: 0.533).opacity(0.35)

    /// Recording state color — same as accentAmber but named for semantic clarity.
    static let accentRecording = accentAmber

    // TODO: Halide Phase 2 — Color(red: 130/255, green: 168/255, blue: 185/255)
    /// Idle waveform line color (cool slate). Phase 2: rgb(130,168,185).
    static let accentIdle = Color(red: 0, green: 1, blue: 0.533).opacity(0.4)

    /// Destructive action color — always system red.
    static let accentDestructive = Color(nsColor: .systemRed)

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
// swiftlint:enable todo
