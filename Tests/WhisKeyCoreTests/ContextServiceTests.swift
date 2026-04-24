import Testing
@testable import WhisKeyCore

struct ContextServiceTests {

    private let service = ContextService()

    // MARK: - suggestedToneStyle mappings

    @Test func slackMapsToCasual() {
        #expect(service.suggestedToneStyle(for: "com.tinyspeck.slackmacgap") == .casual)
    }

    @Test func appleMessagesMapsToCasual() {
        #expect(service.suggestedToneStyle(for: "com.apple.Messages") == .casual)
    }

    @Test func vscodeMapToTechnical() {
        #expect(service.suggestedToneStyle(for: "com.microsoft.VSCode") == .technical)
    }

    @Test func githubClientMapsToTechnical() {
        #expect(service.suggestedToneStyle(for: "com.github.GitHubClient") == .technical)
    }

    @Test func terminalMapsToTechnical() {
        #expect(service.suggestedToneStyle(for: "com.apple.Terminal") == .technical)
    }

    @Test func mailMapsToProfessional() {
        #expect(service.suggestedToneStyle(for: "com.apple.mail") == .professional)
    }

    @Test func notionMapsToProfessional() {
        #expect(service.suggestedToneStyle(for: "notion.id") == .professional)
    }

    @Test func wordMapsToProfessional() {
        #expect(service.suggestedToneStyle(for: "com.microsoft.Word") == .professional)
    }

    @Test func unknownAppMapsToCasual() {
        #expect(service.suggestedToneStyle(for: "com.random.unknownapp") == .casual)
    }

    @Test func emptyBundleIDMapsToCasual() {
        #expect(service.suggestedToneStyle(for: "") == .casual)
    }
}
