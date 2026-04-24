@testable import WhisKeyCore
import XCTest

class HotkeyManagerTests: XCTestCase {

    // MARK: - Mode enumeration

    func testModeEnumCasesExist() {
        let manager = HotkeyManager()
        manager.mode = .pushToTalk
        manager.mode = .toggle
        // Compile-time proof both cases exist
    }

    // MARK: - Default configuration

    func testDefaultModePushToTalk() {
        let manager = HotkeyManager()
        XCTAssertEqual(manager.mode, .pushToTalk)
    }

    func testDefaultWatchedKeyCode() {
        let manager = HotkeyManager()
        XCTAssertEqual(manager.watchedKeyCode, 0x3D) // Right Option
    }

    // MARK: - Mutability

    func testModeCanBeChanged() {
        let manager = HotkeyManager()
        manager.mode = .toggle
        XCTAssertEqual(manager.mode, .toggle)
        manager.mode = .pushToTalk
        XCTAssertEqual(manager.mode, .pushToTalk)
    }

    func testWatchedKeyCodeCanBeChanged() {
        let manager = HotkeyManager()
        manager.watchedKeyCode = 0x00 // A key
        XCTAssertEqual(manager.watchedKeyCode, 0x00)
    }

    // MARK: - Callbacks

    func testOnStartRecordingCallbackCanBeSet() {
        let manager = HotkeyManager()
        var called = false
        manager.onStartRecording = { called = true }
        manager.onStartRecording?()
        XCTAssertTrue(called)
    }

    func testOnStopRecordingCallbackCanBeSet() {
        let manager = HotkeyManager()
        var called = false
        manager.onStopRecording = { called = true }
        manager.onStopRecording?()
        XCTAssertTrue(called)
    }

    func testCallbacksCanBeCleared() {
        let manager = HotkeyManager()
        manager.onStartRecording = { }
        manager.onStartRecording = nil
        XCTAssertNil(manager.onStartRecording)
    }

    func testCallbackMultipleInvocations() {
        let manager = HotkeyManager()
        var count = 0
        manager.onStartRecording = { count += 1 }
        manager.onStartRecording?()
        manager.onStartRecording?()
        manager.onStartRecording?()
        XCTAssertEqual(count, 3)
    }

    func testIndependentCallbacks() {
        let manager = HotkeyManager()
        var startCount = 0
        var stopCount = 0
        manager.onStartRecording = { startCount += 1 }
        manager.onStopRecording = { stopCount += 1 }
        manager.onStartRecording?()
        manager.onStopRecording?()
        manager.onStartRecording?()
        XCTAssertEqual(startCount, 2)
        XCTAssertEqual(stopCount, 1)
    }

    // MARK: - Lifecycle

    // Disabled: Depends on system Input Monitoring state — CGEventTap succeeds when permission is granted.
    // Manual test: grant Input Monitoring, run testStartReturnsFalseWithoutInputMonitoring, expect false.
    func testStartReturnsFalseWithoutInputMonitoring() throws {
        throw XCTSkip("Depends on system Input Monitoring state — CGEventTap succeeds when permission is granted")
    }

    func testStopSafeWithoutStart() {
        let manager = HotkeyManager()
        manager.stop() // Must not crash
    }

    func testMultipleStopsAreSafe() {
        let manager = HotkeyManager()
        manager.stop()
        manager.stop()
        manager.stop()
    }

    func testConfigurationPersistsAcrossLifecycle() {
        let manager = HotkeyManager()
        manager.mode = .toggle
        manager.watchedKeyCode = 0x01
        _ = manager.start() // expected false in test env
        XCTAssertEqual(manager.mode, .toggle)
        XCTAssertEqual(manager.watchedKeyCode, 0x01)
        manager.stop()
        XCTAssertEqual(manager.mode, .toggle)
        XCTAssertEqual(manager.watchedKeyCode, 0x01)
    }
}
