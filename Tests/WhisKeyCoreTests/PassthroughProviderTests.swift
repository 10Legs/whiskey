import XCTest
@testable import WhisKeyCore

final class PassthroughProviderTests: XCTestCase {

    private let provider = PassthroughProvider()
    private let context  = InjectionContext(
        activeAppName: "Test",
        activeAppBundleID: "com.test.app",
        focusedFieldContent: nil
    )

    func testReturnsRawTranscriptUnchanged() async throws {
        let input = "um yeah so like I wanted to talk about this thing"
        let result = try await provider.cleanup(
            rawTranscript: input,
            context: context,
            profile: CleanupProfile()
        )
        XCTAssertEqual(result, input)
    }

    func testReturnsEmptyStringUnchanged() async throws {
        let result = try await provider.cleanup(
            rawTranscript: "",
            context: context,
            profile: CleanupProfile()
        )
        XCTAssertEqual(result, "")
    }

    func testRawModeProfileAlsoReturnsUnchanged() async throws {
        let input = "hello world"
        let result = try await provider.cleanup(
            rawTranscript: input,
            context: context,
            profile: .passthrough
        )
        XCTAssertEqual(result, input)
    }
}
