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
}
