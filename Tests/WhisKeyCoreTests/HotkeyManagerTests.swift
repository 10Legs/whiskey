import Testing
@testable import WhisKeyCore

@Suite struct HotkeyManagerTests {

    // MARK: - Mode enumeration

    @Test func modeEnumCasesExist() {
        let manager = HotkeyManager()
        manager.mode = .pushToTalk
        manager.mode = .toggle
        // Compile-time proof both cases exist
    }

    // MARK: - Default configuration

    @Test func defaultModePushToTalk() {
        let manager = HotkeyManager()
        #expect(manager.mode == .pushToTalk)
    }

    @Test func defaultWatchedKeyCode() {
        let manager = HotkeyManager()
        #expect(manager.watchedKeyCode == 0x3D) // Right Option
    }

    // MARK: - Mutability

    @Test func modeCanBeChanged() {
        let manager = HotkeyManager()
        manager.mode = .toggle
        #expect(manager.mode == .toggle)
        manager.mode = .pushToTalk
        #expect(manager.mode == .pushToTalk)
    }

    @Test func watchedKeyCodeCanBeChanged() {
        let manager = HotkeyManager()
        manager.watchedKeyCode = 0x00 // A key
        #expect(manager.watchedKeyCode == 0x00)
    }

    // MARK: - Callbacks

    @Test func onStartRecordingCallbackCanBeSet() {
        let manager = HotkeyManager()
        var called = false
        manager.onStartRecording = { called = true }
        manager.onStartRecording?()
        #expect(called)
    }

    @Test func onStopRecordingCallbackCanBeSet() {
        let manager = HotkeyManager()
        var called = false
        manager.onStopRecording = { called = true }
        manager.onStopRecording?()
        #expect(called)
    }

    @Test func callbacksCanBeCleared() {
        let manager = HotkeyManager()
        manager.onStartRecording = { }
        manager.onStartRecording = nil
        #expect(manager.onStartRecording == nil)
    }

    @Test func callbackMultipleInvocations() {
        let manager = HotkeyManager()
        var count = 0
        manager.onStartRecording = { count += 1 }
        manager.onStartRecording?()
        manager.onStartRecording?()
        manager.onStartRecording?()
        #expect(count == 3)
    }

    @Test func independentCallbacks() {
        let manager = HotkeyManager()
        var startCount = 0
        var stopCount = 0
        manager.onStartRecording = { startCount += 1 }
        manager.onStopRecording = { stopCount += 1 }
        manager.onStartRecording?()
        manager.onStopRecording?()
        manager.onStartRecording?()
        #expect(startCount == 2)
        #expect(stopCount == 1)
    }

    // MARK: - Lifecycle

    @Test func startReturnsFalseWithoutInputMonitoring() {
        let manager = HotkeyManager()
        // Event tap creation fails without Input Monitoring permission in test env
        #expect(!manager.start())
    }

    @Test func stopSafeWithoutStart() {
        let manager = HotkeyManager()
        manager.stop() // Must not crash
    }

    @Test func multipleStopsAreSafe() {
        let manager = HotkeyManager()
        manager.stop()
        manager.stop()
        manager.stop()
    }

    @Test func configurationPersistsAcrossLifecycle() {
        let manager = HotkeyManager()
        manager.mode = .toggle
        manager.watchedKeyCode = 0x01
        _ = manager.start() // expected false in test env
        #expect(manager.mode == .toggle)
        #expect(manager.watchedKeyCode == 0x01)
        manager.stop()
        #expect(manager.mode == .toggle)
        #expect(manager.watchedKeyCode == 0x01)
    }
}
