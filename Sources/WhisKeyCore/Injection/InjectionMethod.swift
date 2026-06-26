/// Selects which injection strategy `TextInjector` uses for a given app.
/// `.auto` runs the full AX → Pasteboard → CGEvent waterfall (legacy behaviour).
/// All other cases pin a single strategy and fall through to lower strategies on
/// failure — they never hard-fail and never silently drop the user's dictation.
///
/// See ADR-009: Per-App Injection-Method Override.
public enum InjectionMethod: String, Codable, CaseIterable, Sendable {
    case auto
    case ax
    case pasteboard
    case cgEvent
}

// MARK: - Display helpers

public extension InjectionMethod {
    /// Short label used in the settings picker.
    var displayName: String {
        switch self {
        case .auto:       return "Automatic (recommended)"
        case .pasteboard: return "Paste (Cmd-V)"
        case .ax:         return "Accessibility (direct)"
        case .cgEvent:    return "Simulated typing"
        }
    }
}
