import Foundation

/// Protocol all LLM cleanup backends must conform to.
///
/// Implementations are responsible for taking a raw Whisper transcript and returning
/// a cleaned version according to the provided `CleanupProfile`. If cleanup cannot be
/// performed for any reason, implementations MUST return `rawTranscript` unchanged
/// rather than throwing — only hard, non-recoverable failures should propagate.
public protocol LLMProvider: Sendable {
    func cleanup(
        rawTranscript: String,
        context: InjectionContext,
        profile: CleanupProfile
    ) async throws -> String

    func warmUp() async
}

public extension LLMProvider {
    func warmUp() async {}
}
