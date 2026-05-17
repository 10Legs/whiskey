import Foundation

/// Per-app tone profile controlling LLM cleanup style.
///
/// Each case produces a distinct `systemPromptSuffix` that is appended to
/// the base LLM cleanup system prompt before the request is dispatched.
/// The `.raw` case bypasses the LLM entirely.
public enum ToneProfile: String, Codable, CaseIterable, Sendable {

    /// Conversational, natural output. Contractions kept.
    case casual

    /// Professional, formal language. Proper grammar enforced.
    case formal

    /// Preserve technical terms, variable names, and identifiers exactly.
    case code

    /// Skip LLM cleanup — inject the raw Whisper transcript verbatim.
    case raw

    // MARK: - Display

    public var displayName: String {
        switch self {
        case .casual:  return "Casual"
        case .formal:  return "Formal"
        case .code:    return "Code"
        case .raw:     return "Raw (no cleanup)"
        }
    }

    // MARK: - Prompt

    /// Suffix appended to the LLM cleanup system prompt.
    /// Empty for `.raw` — that case bypasses the LLM and this value is unused.
    public var systemPromptSuffix: String {
        switch self {
        case .casual:
            return " Rewrite casually, conversational tone, use contractions."
        case .formal:
            return " Rewrite formally, professional tone, proper grammar."
        case .code:
            return " Preserve code syntax, variable names, and function signatures exactly."
        case .raw:
            return ""
        }
    }
}
