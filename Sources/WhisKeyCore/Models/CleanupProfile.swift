import Foundation

// MARK: - ToneStyle

/// Describes the cleanup tone applied by the LLM post-processing step.
public enum ToneStyle: String, Sendable, CaseIterable {
    case casual
    case professional
    case technical
    case literal

    /// System prompt injected as the first message in the LLM request.
    public var systemPrompt: String {
        switch self {
        case .casual:
            return """
            You are a voice transcription cleanup assistant. Fix only obvious sentence fragments \
            and add basic punctuation. Keep the text conversational and natural. \
            Output ONLY the cleaned text — no explanation, no quotes, no prefix.
            """
        case .professional:
            return """
            You are a voice transcription cleanup assistant. Fix grammar, remove filler words \
            (um, uh, like, you know, basically, actually), add punctuation, and capitalize \
            sentences. Output ONLY the cleaned text — no explanation, no quotes, no prefix.
            """
        case .technical:
            return """
            You are a voice transcription cleanup assistant. Fix grammar, remove filler words \
            (um, uh, like, you know, basically, actually), add punctuation, and capitalize \
            sentences. Preserve technical terms, variable names, and command syntax exactly. \
            Output ONLY the cleaned text — no explanation, no quotes, no prefix.
            """
        case .literal:
            return ""
        }
    }
}

// MARK: - CleanupProfile

/// Controls the behaviour of the LLM post-processing step for a transcription.
public struct CleanupProfile: Sendable {

    /// Remove common filler words: "um", "uh", "like", "you know", "basically", "actually".
    public var removeFillers: Bool

    /// Add sentence-ending punctuation and capitalize sentence starts.
    public var addPunctuation: Bool

    /// Stylistic register applied during cleanup.
    public var toneStyle: ToneStyle

    /// When `true`, skip the LLM entirely and inject the raw transcript verbatim.
    public var rawMode: Bool

    /// Optional override for the LLM system prompt (S4-T7).
    ///
    /// When non-nil, LLM providers must use this string as the system prompt
    /// instead of `toneStyle.systemPrompt`. Set by `ToneProfileCleanupWrapper`
    /// to inject the per-app tone suffix without mutating `ToneStyle`.
    public var customSystemPrompt: String?

    /// The effective system prompt: `customSystemPrompt` when set, otherwise `toneStyle.systemPrompt`.
    public var effectiveSystemPrompt: String {
        customSystemPrompt ?? toneStyle.systemPrompt
    }

    public init(
        removeFillers: Bool = true,
        addPunctuation: Bool = true,
        toneStyle: ToneStyle = .casual,
        rawMode: Bool = false,
        customSystemPrompt: String? = nil
    ) {
        self.removeFillers = removeFillers
        self.addPunctuation = addPunctuation
        self.toneStyle = toneStyle
        self.rawMode = rawMode
        self.customSystemPrompt = customSystemPrompt
    }

    /// Convenience profile that bypasses all LLM processing.
    public static let passthrough = CleanupProfile(rawMode: true)
}
