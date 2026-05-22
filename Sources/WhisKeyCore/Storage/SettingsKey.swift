import Foundation

/// Known settings keys for the key-value settings store.
public enum SettingsKey: String, Sendable, CaseIterable {
    case whisperModel
    case languageHint
    case llmProvider
    case toneStyle
    case removeFillers
    case addPunctuation
    case rawMode
    case outputMode
    case notificationsEnabled
    case activeModelID
    case llmEnabled
    /// Maximum number of history entries to retain. Older entries are trimmed on insert.
    /// Default: 500. Valid range: 50–10000.
    case historyRetentionMax
    case silenceTrimEnabled
    case fillerScrubberEnabled
    case appProfiles
    /// Hands-free mode enabled flag. Default: true. (S3-T4)
    case handsFreeEnabled
    /// Double-tap disambiguation window milliseconds. Default: 300. Range: 200-500. (S3-T4)
    case disambiguationWindowMs
    case hudEnabled
    /// Controls how long the live-preview caption strip lingers after injection.
    /// P1: key declared here; accessor added in P2.
    case previewLingerMode
}
