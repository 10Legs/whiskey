import Foundation

/// Thin `LLMProvider` decorator that appends a per-app `ToneProfile` suffix to
/// the base system prompt before forwarding to the underlying provider.
///
/// The combined prompt is injected via `CleanupProfile.customSystemPrompt` so
/// every provider reads it from `profile.effectiveSystemPrompt` without needing
/// to know about `ToneProfile` at all.
///
/// Implemented as an actor to satisfy `LLMProvider: Sendable`.
actor ToneProfileCleanupWrapper: LLMProvider {

    private let base: any LLMProvider
    private let suffix: String

    init(base: any LLMProvider, suffix: String) {
        self.base = base
        self.suffix = suffix
    }

    func cleanup(
        rawTranscript: String,
        context: InjectionContext,
        profile: CleanupProfile
    ) async throws -> String {
        // Append the tone suffix to whichever system prompt the profile currently resolves to.
        let combined = profile.effectiveSystemPrompt + suffix
        var modifiedProfile = profile
        modifiedProfile.customSystemPrompt = combined
        return try await base.cleanup(
            rawTranscript: rawTranscript,
            context: context,
            profile: modifiedProfile
        )
    }

    func warmUp() async {
        await base.warmUp()
    }
}
