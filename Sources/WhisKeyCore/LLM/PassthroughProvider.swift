import Foundation

/// An `LLMProvider` that performs no cleanup — returns the raw transcript unchanged.
///
/// Used when `CleanupProfile.rawMode` is `true` or when no LLM backend is configured.
public struct PassthroughProvider: LLMProvider {

    public init() {}

    public func cleanup(
        rawTranscript: String,
        context: InjectionContext,
        profile: CleanupProfile
    ) async throws -> String {
        return rawTranscript
    }
}
