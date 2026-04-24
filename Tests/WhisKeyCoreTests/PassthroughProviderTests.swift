import Testing
@testable import WhisKeyCore

struct PassthroughProviderTests {

    private let provider = PassthroughProvider()
    private let context = InjectionContext(
        activeAppName: "Test",
        activeAppBundleID: "com.test.app",
        focusedFieldContent: nil
    )

    @Test func returnsRawTranscriptUnchanged() async throws {
        let input = "um yeah so like I wanted to talk about this thing"
        let result = try await provider.cleanup(
            rawTranscript: input,
            context: context,
            profile: CleanupProfile()
        )
        #expect(result == input)
    }

    @Test func returnsEmptyStringUnchanged() async throws {
        let result = try await provider.cleanup(
            rawTranscript: "",
            context: context,
            profile: CleanupProfile()
        )
        #expect(result == "")
    }

    @Test func rawModeProfileAlsoReturnsUnchanged() async throws {
        let input = "hello world"
        let result = try await provider.cleanup(
            rawTranscript: input,
            context: context,
            profile: .passthrough
        )
        #expect(result == input)
    }
}
