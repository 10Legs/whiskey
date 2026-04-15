import Foundation

/// Known settings keys for the key-value settings store.
public enum SettingsKey: String, Sendable, CaseIterable {
    case whisperModel     = "whisperModel"
    case languageHint     = "languageHint"
    case llmProvider      = "llmProvider"
    case toneStyle        = "toneStyle"
    case removeFillers    = "removeFillers"
    case addPunctuation   = "addPunctuation"
    case rawMode          = "rawMode"
}
