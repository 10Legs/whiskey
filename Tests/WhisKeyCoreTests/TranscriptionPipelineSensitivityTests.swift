@testable import WhisKeyCore
import XCTest

/// Tests for S5-SEC-1 and S5-SEC-2 — SensitiveAppRegistry guards added to
/// `TranscriptionPipeline.reinjectText` and `TranscriptionPipeline.executeVoiceCommands`.
///
/// Full end-to-end execution requires:
///   - A live Whisper model on disk
///   - Accessibility permission granted to the test runner
///   - A real frontmost application whose bundle ID is in `SensitiveAppRegistry.blocklist`
///
/// Those conditions cannot be satisfied in CI.  The tests below are disabled with
/// `.disabled()` and documented so QA can verify manually on a real device.
/// The security invariants are pinned by `SensitiveAppRegistryTests` which run
/// without hardware dependencies.
final class TranscriptionPipelineSensitivityTests: XCTestCase {

    // MARK: - S5-SEC-1: reinjectText blocks injection in sensitive apps

    /// Manual verification (S5-SEC-1):
    ///
    /// 1. Launch WhisKey in Debug build.
    /// 2. Make Keychain Access (or 1Password) the frontmost app.
    /// 3. Trigger the `injectLastTranscription` hotkey.
    /// 4. Confirm no text is injected and "re-injection blocked" appears in the
    ///    file log (`~/Library/Logs/WhisKey/whiskey.log`).
    /// 5. Repeat with Terminal (com.apple.Terminal) and iTerm2.
    ///
    /// - Note: Disabled because it requires Accessibility permission, a live
    ///   Whisper model, and manual control of the frontmost application.
    func testReinjectTextDoesNotInjectInSensitiveApp() throws {
        throw XCTSkip(
            "S5-SEC-1: Hardware/permission dependent. " +
            "Verify manually: trigger injectLastTranscription hotkey while " +
            "Terminal or a password manager is frontmost; confirm no injection " +
            "and a warning log entry."
        )
    }

    // MARK: - S5-SEC-2: executeVoiceCommands blocks injection in sensitive apps

    /// Manual verification (S5-SEC-2):
    ///
    /// 1. Launch WhisKey in Debug build.
    /// 2. Make Terminal (com.apple.Terminal) the frontmost app with a command
    ///    partially typed (e.g., `rm -rf `).
    /// 3. Dictate "new line" while recording.
    /// 4. Confirm the command was NOT submitted (no `\n` injected) and
    ///    "voice commands blocked" appears in the file log.
    /// 5. Repeat with "new paragraph" and with iTerm2.
    /// 6. Repeat with a password manager (1Password, Bitwarden) to confirm
    ///    all AX-injection voice commands are suppressed.
    ///
    /// - Note: Disabled because it requires Accessibility permission, a live
    ///   Whisper model, and manual control of the frontmost application.
    func testVoiceCommandsDoNotInjectInSensitiveApp() throws {
        throw XCTSkip(
            "S5-SEC-2: Hardware/permission dependent. " +
            "Verify manually: dictate 'new line' while Terminal is frontmost; " +
            "confirm the shell command is NOT submitted and a warning log entry " +
            "appears."
        )
    }
}
