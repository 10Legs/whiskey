import Foundation
import Testing
@testable import WhisKeyCore

struct OllamaProviderTests {

    private let context = InjectionContext(
        activeAppName: "Test",
        activeAppBundleID: "com.test.app",
        focusedFieldContent: nil
    )

    // MARK: - Fallback on network failure

    /// When Ollama is not running, provider returns raw transcript rather than throwing.
    /// Points at an unreachable port — connection is refused immediately (not a timeout).
    @Test func fallsBackToRawTranscriptOnConnectionFailure() async throws {
        let provider = OllamaProvider(
            modelName: "llama3.2",
            baseURL: URL(string: "http://127.0.0.1:19999")! // swiftlint:disable:this force_unwrapping
        )
        let input = "uh so basically I wanted to say hello"
        let result = try await provider.cleanup(
            rawTranscript: input,
            context: context,
            profile: CleanupProfile()
        )
        #expect(result == input, "OllamaProvider should return raw transcript on network failure")
    }

    // MARK: - rawMode short-circuit

    @Test func rawModeSkipsLLMCall() async throws {
        let provider = OllamaProvider()
        let input = "um yeah so like"
        let result = try await provider.cleanup(
            rawTranscript: input,
            context: context,
            profile: .passthrough
        )
        #expect(result == input)
    }

    // MARK: - .literal tone short-circuit

    @Test func literalToneSkipsLLMCall() async throws {
        let provider = OllamaProvider(
            baseURL: URL(string: "http://127.0.0.1:19999")! // swiftlint:disable:this force_unwrapping
        )
        let input = "no cleanup please"
        let profile = CleanupProfile(toneStyle: .literal)
        let result = try await provider.cleanup(
            rawTranscript: input,
            context: context,
            profile: profile
        )
        #expect(result == input)
    }
}
