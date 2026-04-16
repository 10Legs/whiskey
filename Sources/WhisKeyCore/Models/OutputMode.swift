/// Determines where transcribed text is dispatched after processing.
public enum OutputMode: String, Codable, Sendable, CaseIterable {
    /// Inject text into the focused window via AX / pasteboard / CGEvent chain.
    case activeWindow
    /// Copy text to clipboard only; do not inject into any window.
    case clipboard
    /// Inject into the focused window AND leave a copy on the clipboard.
    case both
    /// Transcribe and show in HUD/history only; do not inject or copy to clipboard.
    case hudOnly
}
