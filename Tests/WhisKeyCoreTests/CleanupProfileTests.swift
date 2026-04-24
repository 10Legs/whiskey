import Testing
@testable import WhisKeyCore

struct CleanupProfileTests {

    // MARK: - ToneStyle.systemPrompt

    @Test func casualSystemPromptIsNonEmpty() {
        #expect(!ToneStyle.casual.systemPrompt.isEmpty)
    }

    @Test func professionalSystemPromptIsNonEmpty() {
        #expect(!ToneStyle.professional.systemPrompt.isEmpty)
    }

    @Test func technicalSystemPromptIsNonEmpty() {
        #expect(!ToneStyle.technical.systemPrompt.isEmpty)
    }

    @Test func literalSystemPromptIsEmpty() {
        #expect(ToneStyle.literal.systemPrompt.isEmpty)
    }

    @Test func allCasesHaveDefinedSystemPrompts() {
        for style in ToneStyle.allCases where style != .literal {
            #expect(!style.systemPrompt.isEmpty, "\(style) should have a non-empty system prompt")
        }
    }

    // MARK: - CleanupProfile defaults

    @Test func defaultProfileHasCleanupEnabled() {
        let profile = CleanupProfile()
        #expect(profile.removeFillers)
        #expect(profile.addPunctuation)
        #expect(!profile.rawMode)
        #expect(profile.toneStyle == .casual)
    }

    @Test func passthroughProfileHasRawModeEnabled() {
        let profile = CleanupProfile.passthrough
        #expect(profile.rawMode)
    }
}
