import Foundation

/// Named actions that can be bound to a global hotkey.
///
/// Raw values are stable identifiers used in `UserDefaults` serialisation.
/// **Do not rename raw values** — doing so silently drops persisted user bindings.
public enum HotkeyAction: String, CaseIterable, Codable, Sendable {
    /// Default push-to-talk / hold-vs-tap transcription (the original Right Option behaviour).
    case defaultTranscription

    /// Hands-free toggle — starts the state machine's hands-free path directly,
    /// bypassing the double-tap gesture required via the default binding.
    case handsFreeTranscription

    /// Opens (or toggles) the menu-bar popover.
    case openPopover

    /// Re-injects the most recent transcription result into the active field.
    case injectLastTranscription

    // MARK: - Display

    public var displayName: String {
        switch self {
        case .defaultTranscription:     return "Default Transcription"
        case .handsFreeTranscription:   return "Hands-Free Transcription"
        case .openPopover:              return "Open WhisKey Popover"
        case .injectLastTranscription:  return "Inject Last Transcription"
        }
    }
}
