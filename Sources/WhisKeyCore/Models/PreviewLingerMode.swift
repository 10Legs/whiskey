import Foundation

/// Controls how long the live-preview caption strip remains visible after
/// the final Whisper transcript is injected.
///
/// P1 hardcodes `.untilInjected`. P2 will add Settings persistence via
/// `SettingsKey.previewLingerMode` and a `SettingsManager` accessor.
public enum PreviewLingerMode: Codable, Sendable, Equatable {
    /// Clear immediately when recording stops (before Whisper completes).
    case immediate
    /// Clear after the final transcript is injected (P1 default).
    case untilInjected
    /// Clear after a fixed delay following injection.
    case linger(seconds: Double)
    /// Hold on error until the user dismisses. Reserved for P2.
    case errorHold
}
