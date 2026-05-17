@testable import WhisKeyCore
import XCTest

final class SensitiveAppRegistryTests: XCTestCase {

    // MARK: - Blocklist membership

    func testKeychainAccessIsBlocked() {
        XCTAssertTrue(SensitiveAppRegistry.isSensitive("com.apple.keychainaccess"))
    }

    func testSystemPreferencesIsBlocked() {
        XCTAssertTrue(SensitiveAppRegistry.isSensitive("com.apple.systempreferences"))
    }

    func testTerminalIsBlocked() {
        XCTAssertTrue(SensitiveAppRegistry.isSensitive("com.apple.Terminal"))
    }

    func testITermIsBlocked() {
        XCTAssertTrue(SensitiveAppRegistry.isSensitive("com.googlecode.iterm2"))
    }

    func testOnePassword7IsBlocked() {
        XCTAssertTrue(SensitiveAppRegistry.isSensitive("com.agilebits.onepassword7"))
    }

    func testOnePasswordMacIsBlocked() {
        XCTAssertTrue(SensitiveAppRegistry.isSensitive("com.agilebits.onepassword-osx"))
    }

    func testOnePassword8IsBlocked() {
        XCTAssertTrue(SensitiveAppRegistry.isSensitive("com.1password.1password"))
    }

    func testBitwardenIsBlocked() {
        XCTAssertTrue(SensitiveAppRegistry.isSensitive("com.bitwarden.desktop"))
    }

    func testKeePassXCIsBlocked() {
        XCTAssertTrue(SensitiveAppRegistry.isSensitive("org.keepassxc.keepassxc"))
    }

    func testAuthyIsBlocked() {
        XCTAssertTrue(SensitiveAppRegistry.isSensitive("com.authy.authy-mac"))
    }

    func testMicrosoftAuthenticatorIsBlocked() {
        XCTAssertTrue(SensitiveAppRegistry.isSensitive("com.microsoft.authenticator"))
    }

    func testSecurityAgentIsBlocked() {
        XCTAssertTrue(SensitiveAppRegistry.isSensitive("com.apple.SecurityAgent"))
    }

    // MARK: - Safe targets

    func testSafariIsNotBlocked() {
        XCTAssertFalse(SensitiveAppRegistry.isSensitive("com.apple.Safari"))
    }

    func testNotesIsNotBlocked() {
        XCTAssertFalse(SensitiveAppRegistry.isSensitive("com.apple.Notes"))
    }

    func testXcodeIsNotBlocked() {
        XCTAssertFalse(SensitiveAppRegistry.isSensitive("com.apple.dt.Xcode"))
    }

    func testSlackIsNotBlocked() {
        XCTAssertFalse(SensitiveAppRegistry.isSensitive("com.tinyspeck.slackmacgap"))
    }

    // MARK: - Nil bundle ID

    func testNilBundleIDIsNotBlocked() {
        // A nil bundle ID must not be treated as sensitive — unknown apps should
        // not be silently blocked.
        XCTAssertFalse(SensitiveAppRegistry.isSensitive(nil))
    }

    // MARK: - Blocklist is non-empty

    func testBlocklistIsNonEmpty() {
        XCTAssertFalse(SensitiveAppRegistry.blocklist.isEmpty)
    }

    // MARK: - Case sensitivity

    func testBundleIDMatchIsCaseSensitive() {
        // Bundle IDs are case-sensitive on macOS; a wrong-case variant must not match.
        XCTAssertFalse(SensitiveAppRegistry.isSensitive("com.apple.terminal"))
        XCTAssertFalse(SensitiveAppRegistry.isSensitive("COM.APPLE.TERMINAL"))
    }
}
