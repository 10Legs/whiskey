@testable import WhisKeyCore
import XCTest

// MARK: - HotkeyManager State Machine Tests (S3-T4)
//
// These tests exercise the timing-based hold-vs-tap state machine by directly
// calling internal event-simulation helpers. CGEventTap itself cannot be created
// in the test environment (no Input Monitoring permission), so state machine
// logic is validated through the `simulateKeyDown` / `simulateKeyUp` test shims.
//
// Hardware-dependent tests (actual Right Option key events via CGEventTap):
//   MANUAL TEST: grant Input Monitoring, install the tap with hotkey.start(),
//   hold Right Option >300ms → verify onStartRecording fires, release → onStopRecording.
//   Double-tap Right Option within 300ms → verify onHandsFreeStart fires.
//   Third tap while hands-free → verify onHandsFreeStop fires.

class HotkeyManagerTests: XCTestCase {

    // MARK: - Default configuration

    func testDefaultWatchedKeyCode() {
        let manager = HotkeyManager()
        XCTAssertEqual(manager.watchedKeyCode, 0x3D) // Right Option
    }

    func testDefaultDisambiguationWindow() {
        let manager = HotkeyManager()
        XCTAssertEqual(manager.disambiguationWindowMs, 300.0)
    }

    func testDefaultMinIntentionalTapMs() {
        let manager = HotkeyManager()
        XCTAssertEqual(manager.minIntentionalTapMs, 80.0)
    }

    func testDisambiguationWindowCanBeChanged() {
        let manager = HotkeyManager()
        manager.disambiguationWindowMs = 400.0
        XCTAssertEqual(manager.disambiguationWindowMs, 400.0)
    }

    func testWatchedKeyCodeCanBeChanged() {
        let manager = HotkeyManager()
        manager.watchedKeyCode = 0x00
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

    func testOnHandsFreeStartCallbackCanBeSet() {
        let manager = HotkeyManager()
        var called = false
        manager.onHandsFreeStart = { called = true }
        manager.onHandsFreeStart?()
        XCTAssertTrue(called)
    }

    func testOnHandsFreeStopCallbackCanBeSet() {
        let manager = HotkeyManager()
        var called = false
        manager.onHandsFreeStop = { called = true }
        manager.onHandsFreeStop?()
        XCTAssertTrue(called)
    }

    func testCallbacksCanBeCleared() {
        let manager = HotkeyManager()
        manager.onStartRecording = { }
        manager.onStartRecording = nil
        XCTAssertNil(manager.onStartRecording)
        manager.onHandsFreeStart = { }
        manager.onHandsFreeStart = nil
        XCTAssertNil(manager.onHandsFreeStart)
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

    // Disabled: Depends on system Input Monitoring state.
    // Manual test: grant Input Monitoring, run app, hold Right Option >300ms → onStartRecording fires;
    // release → onStopRecording fires.
    func testStartReturnsFalseWithoutInputMonitoring() throws {
        throw XCTSkip(
            "Depends on system Input Monitoring state. " +
            "Manual test: grant Input Monitoring, hold Right Option >300ms → PTT fires."
        )
    }

    // MARK: - State Machine via async timing tests
    //
    // These tests use Task.sleep to simulate real timing through the state machine.
    // The disambiguation window is set short (100-150ms) for test speed.

    /// PTT: key held > disambiguationWindowMs → onStartRecording fires; key released → onStopRecording fires.
    func testPushToTalkHoldAndRelease() async throws {
        let manager = HotkeyManager()
        manager.disambiguationWindowMs = 100

        var startFired = false
        var stopFired = false
        manager.onStartRecording = { startFired = true }
        manager.onStopRecording = { stopFired = true }

        manager.simulateKeyDown()
        try await Task.sleep(for: .milliseconds(150))

        XCTAssertTrue(startFired, "onStartRecording must fire after hold window expires")
        XCTAssertFalse(stopFired, "onStopRecording must not fire until key is released")

        manager.simulateKeyUp()
        XCTAssertTrue(stopFired, "onStopRecording must fire on key release from holding state")
    }

    /// Accidental tap: key down < 80ms → no callbacks fire.
    func testAccidentalTapUnder80msIsDropped() async throws {
        let manager = HotkeyManager()
        manager.disambiguationWindowMs = 300

        var startFired = false
        var handsFreeStartFired = false
        manager.onStartRecording = { startFired = true }
        manager.onHandsFreeStart = { handsFreeStartFired = true }

        manager.simulateKeyDown()
        try await Task.sleep(for: .milliseconds(40)) // well under 80ms
        manager.simulateKeyUp()

        try await Task.sleep(for: .milliseconds(350)) // past disambiguation window

        XCTAssertFalse(startFired, "onStartRecording must not fire for press < 80ms")
        XCTAssertFalse(handsFreeStartFired, "onHandsFreeStart must not fire for press < 80ms")
    }

    /// Single tap: one valid tap (>= 80ms), wait past window, no second tap → no callbacks fire.
    func testSingleTapTimeoutDoesNotFireAnyCallback() async throws {
        let manager = HotkeyManager()
        manager.disambiguationWindowMs = 150

        var startFired = false
        var handsFreeStartFired = false
        manager.onStartRecording = { startFired = true }
        manager.onHandsFreeStart = { handsFreeStartFired = true }

        manager.simulateKeyDown()
        try await Task.sleep(for: .milliseconds(90)) // >= 80ms
        manager.simulateKeyUp()

        try await Task.sleep(for: .milliseconds(200)) // past window with no second tap

        XCTAssertFalse(startFired, "Single tap must not fire onStartRecording")
        XCTAssertFalse(handsFreeStartFired, "Single tap must not fire onHandsFreeStart")
    }

    /// Double-tap within window → onHandsFreeStart fires; onStartRecording must NOT fire.
    func testDoubleTapWithinWindowFiresHandsFreeStart() async throws {
        let manager = HotkeyManager()
        manager.disambiguationWindowMs = 300

        var startFired = false
        var handsFreeStartFired = false
        manager.onStartRecording = { startFired = true }
        manager.onHandsFreeStart = { handsFreeStartFired = true }

        // First tap.
        manager.simulateKeyDown()
        try await Task.sleep(for: .milliseconds(90)) // >= 80ms
        manager.simulateKeyUp()

        // Second tap within window.
        try await Task.sleep(for: .milliseconds(80))
        manager.simulateKeyDown()

        XCTAssertFalse(startFired, "PTT onStartRecording must not fire on double-tap")
        XCTAssertTrue(handsFreeStartFired, "onHandsFreeStart must fire on second tap within window")

        manager.stop()
    }

    /// Hands-free stop: tap while in handsFreeRecording → onHandsFreeStop fires.
    func testHandsFreeStopTapFiresHandsFreeStop() async throws {
        let manager = HotkeyManager()
        manager.disambiguationWindowMs = 300

        var handsFreeStopFired = false
        manager.onHandsFreeStop = { handsFreeStopFired = true }

        // Enter handsFreeRecording via double-tap.
        manager.simulateKeyDown()
        try await Task.sleep(for: .milliseconds(90))
        manager.simulateKeyUp()
        try await Task.sleep(for: .milliseconds(80))
        manager.simulateKeyDown() // Second tap — enters handsFreeRecording.
        try await Task.sleep(for: .milliseconds(50))
        manager.simulateKeyUp() // Key up on second press (no effect in handsFreeRecording).

        // Third tap (stop tap) with valid duration.
        try await Task.sleep(for: .milliseconds(50))
        manager.simulateKeyDown()
        try await Task.sleep(for: .milliseconds(90)) // >= 80ms
        manager.simulateKeyUp()

        XCTAssertTrue(handsFreeStopFired, "onHandsFreeStop must fire when tapped during handsFreeRecording")
    }

    /// Sub-80ms tap during hands-free is dropped; recording continues (stop does NOT fire).
    func testShortTapDuringHandsFreeIsDropped() async throws {
        let manager = HotkeyManager()
        manager.disambiguationWindowMs = 300

        var handsFreeStopFired = false
        manager.onHandsFreeStop = { handsFreeStopFired = true }

        // Enter handsFreeRecording.
        manager.simulateKeyDown()
        try await Task.sleep(for: .milliseconds(90))
        manager.simulateKeyUp()
        try await Task.sleep(for: .milliseconds(80))
        manager.simulateKeyDown()
        try await Task.sleep(for: .milliseconds(50))
        manager.simulateKeyUp()

        // Short (< 80ms) stop tap — should be ignored.
        try await Task.sleep(for: .milliseconds(50))
        manager.simulateKeyDown()
        try await Task.sleep(for: .milliseconds(40)) // < 80ms
        manager.simulateKeyUp()

        XCTAssertFalse(handsFreeStopFired, "Sub-80ms tap during hands-free must not fire onHandsFreeStop")

        manager.stop()
    }
}

// MARK: - Test-only simulation shims

extension HotkeyManager {
    /// Simulate a key_down event for testing state machine logic directly.
    /// Resets the debounce clock so rapid successive calls are not filtered.
    /// Only reaches internal state machine — does not invoke CGEventTap.
    func simulateKeyDown() {
        lastStartEdgeMillis = -Double.infinity
        handleKeyDown()
    }

    /// Simulate a key_up event for testing state machine logic directly.
    /// Resets the debounce clock so rapid successive calls are not filtered.
    func simulateKeyUp() {
        lastStopEdgeMillis = -Double.infinity
        handleKeyUp()
    }
}
