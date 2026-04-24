@testable import WhisKeyCore
import XCTest

class ContextServiceTests: XCTestCase {

    private let service = ContextService()

    // MARK: - suggestedToneStyle mappings

    func testSlackMapsToCasual() {
        XCTAssertEqual(service.suggestedToneStyle(for: "com.tinyspeck.slackmacgap"), .casual)
    }

    func testAppleMessagesMapsToCasual() {
        XCTAssertEqual(service.suggestedToneStyle(for: "com.apple.Messages"), .casual)
    }

    func testVscodeMapToTechnical() {
        XCTAssertEqual(service.suggestedToneStyle(for: "com.microsoft.VSCode"), .technical)
    }

    func testGithubClientMapsToTechnical() {
        XCTAssertEqual(service.suggestedToneStyle(for: "com.github.GitHubClient"), .technical)
    }

    func testTerminalMapsToTechnical() {
        XCTAssertEqual(service.suggestedToneStyle(for: "com.apple.Terminal"), .technical)
    }

    func testMailMapsToProfessional() {
        XCTAssertEqual(service.suggestedToneStyle(for: "com.apple.mail"), .professional)
    }

    func testNotionMapsToProfessional() {
        XCTAssertEqual(service.suggestedToneStyle(for: "notion.id"), .professional)
    }

    func testWordMapsToProfessional() {
        XCTAssertEqual(service.suggestedToneStyle(for: "com.microsoft.Word"), .professional)
    }

    func testUnknownAppMapsToCasual() {
        XCTAssertEqual(service.suggestedToneStyle(for: "com.random.unknownapp"), .casual)
    }

    func testEmptyBundleIDMapsToCasual() {
        XCTAssertEqual(service.suggestedToneStyle(for: ""), .casual)
    }
}
