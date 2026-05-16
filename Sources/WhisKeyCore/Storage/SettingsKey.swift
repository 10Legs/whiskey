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
}
