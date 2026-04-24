@testable import WhisKeyCore
import XCTest

class CleanupProfileTests: XCTestCase {

    // MARK: - ToneStyle.systemPrompt

    func testCasualSystemPromptIsNonEmpty() {
        XCTAssertFalse(ToneStyle.casual.systemPrompt.isEmpty)
    }

    func testProfessionalSystemPromptIsNonEmpty() {
        XCTAssertFalse(ToneStyle.professional.systemPrompt.isEmpty)
    }

    func testTechnicalSystemPromptIsNonEmpty() {
        XCTAssertFalse(ToneStyle.technical.systemPrompt.isEmpty)
    }

    func testLiteralSystemPromptIsEmpty() {
        XCTAssertTrue(ToneStyle.literal.systemPrompt.isEmpty)
    }

    func testAllCasesHaveDefinedSystemPrompts() {
        for style in ToneStyle.allCases where style != .literal {
            XCTAssertFalse(style.systemPrompt.isEmpty, "\(style) should have a non-empty system prompt")
        }
    }

    // MARK: - CleanupProfile defaults

    func testDefaultProfileHasCleanupEnabled() {
        let profile = CleanupProfile()
        XCTAssertTrue(profile.removeFillers)
        XCTAssertTrue(profile.addPunctuation)
        XCTAssertFalse(profile.rawMode)
        XCTAssertEqual(profile.toneStyle, .casual)
    }

    func testPassthroughProfileHasRawModeEnabled() {
        let profile = CleanupProfile.passthrough
        XCTAssertTrue(profile.rawMode)
    }
}
