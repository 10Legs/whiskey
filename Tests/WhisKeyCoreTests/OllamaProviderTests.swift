import XCTest
@testable import WhisKeyCore

final class OllamaProviderTests: XCTestCase {

    private let context = InjectionContext(
        activeAppName: "Test",
        activeAppBundleID: "com.test.app",
        focusedFieldContent: nil
    )

    // MARK: - Fallback on network failure

    /// When Ollama is not running (or the port is wrong), the provider must return
    /// the raw transcript rather than throw. We point at an unreachable port to
    /// exercise the failure path without requiring a real Ollama instance.
    func testFallsBackToRawTranscriptOnConnectionFailure() async throws {
        let provider = OllamaProvider(
            modelName: "llama3.2",
            baseURL: URL(string: "http://127.0.0.1:19999")! // nothing listening here
        )
        let input = "uh so basically I wanted to say hello"
        let result = try await provider.cleanup(
            rawTranscript: input,
            context: context,
            profile: CleanupProfile()
        )
        XCTAssertEqual(result, input, "OllamaProvider should return raw transcript on network failure")
    }

    // MARK: - rawMode short-circuit

    func testRawModeSkipsLLMCall() async throws {
        // Even with a reachable base URL, rawMode must return immediately.
        let provider = OllamaProvider()
        let input = "um yeah so like"
        let result = try await provider.cleanup(
            rawTranscript: input,
            context: context,
            profile: .passthrough
        )
        XCTAssertEqual(result, input)
    }

    // MARK: - .literal tone short-circuit

    func testLiteralToneSkipsLLMCall() async throws {
        let provider = OllamaProvider(
            baseURL: URL(string: "http://127.0.0.1:19999")!
        )
        let input = "no cleanup please"
        let profile = CleanupProfile(toneStyle: .literal)
        let result = try await provider.cleanup(
            rawTranscript: input,
            context: context,
            profile: profile
        )
        XCTAssertEqual(result, input)
    }
}
