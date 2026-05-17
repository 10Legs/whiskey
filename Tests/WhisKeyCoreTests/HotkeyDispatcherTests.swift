@testable import WhisKeyCore
import CoreGraphics
import XCTest

// MARK: - HotkeyDispatcherTests (S4-T4)
//
// Tests validate:
//   1. syncBindings() pushes the defaultTranscription keyCode into
//      HotkeyManager.watchedKeyCode.
//   2. syncBindings() wires HotkeyManager.onHandsFreeStart so that firing it
//      invokes the dispatcher's onHandsFreeTranscription callback.
//   3. updateBinding(_:) triggers a re-sync (same assertions as (1)).
//   4. Callbacks for openPopover and injectLastTranscription can be set and
//      retrieved (the secondary CGEventTap cannot be exercised in test without
//      Input Monitoring permission — see hardware note below).
//
// Hardware-dependent tests (require Input Monitoring permission):
//   MANUAL TEST: configure bindings for openPopover (e.g. F6) and
//   injectLastTranscription (e.g. F7), launch the app, press those keys, and
//   confirm the popover opens / the last transcription is re-injected.

@MainActor
class HotkeyDispatcherTests: XCTestCase {

    // MARK: - Helpers

    /// Returns a fresh store backed by an in-memory UserDefaults suite.
    private func makeStore(suite: String = UUID().uuidString) -> HotkeyBindingStore {
        let defaults = UserDefaults(suiteName: suite)!
        return HotkeyBindingStore(defaults: defaults)
    }

    private func makeDispatcher(
        store: HotkeyBindingStore? = nil
    ) -> (HotkeyDispatcher, HotkeyBindingStore, HotkeyManager) {
        let s = store ?? makeStore()
        let mgr = HotkeyManager()
        let dispatcher = HotkeyDispatcher(bindingStore: s, hotkeyManager: mgr)
        return (dispatcher, s, mgr)
    }

    // MARK: - syncBindings: defaultTranscription → watchedKeyCode

    func testSyncBindingsPushesDefaultTranscriptionKeyCode() {
        let (dispatcher, store, mgr) = makeDispatcher()

        let customKeyCode: CGKeyCode = 0x60 // F5
        store.setBinding(HotkeyBinding(action: .defaultTranscription, keyCode: customKeyCode))

        dispatcher.syncBindings()

        XCTAssertEqual(mgr.watchedKeyCode, customKeyCode,
            "syncBindings must push defaultTranscription keyCode into HotkeyManager.watchedKeyCode")
    }

    func testSyncBindingsUsesDefaultKeyCodeWhenNoCustomBinding() {
        let (dispatcher, _, mgr) = makeDispatcher()
        dispatcher.syncBindings()
        // Default is Right Option (0x3D) seeded by HotkeyBindingStore.
        XCTAssertEqual(mgr.watchedKeyCode, CGKeyCode(0x3D),
            "watchedKeyCode must equal the default Right Option key code when no custom binding is set")
    }

    func testSyncBindingsWithNilKeyCodeLeavesWatchedKeyCodeUnchanged() {
        let (dispatcher, store, mgr) = makeDispatcher()
        // Seed a known value first.
        mgr.watchedKeyCode = 0x3D
        // Clear the default binding so keyCode is nil.
        store.clearBinding(for: .defaultTranscription)

        dispatcher.syncBindings()

        // watchedKeyCode should remain 0x3D — no update when keyCode is nil.
        XCTAssertEqual(mgr.watchedKeyCode, CGKeyCode(0x3D),
            "watchedKeyCode must not change when defaultTranscription binding has no keyCode")
    }

    // MARK: - syncBindings: handsFreeTranscription callback wiring

    func testSyncBindingsWiresHandsFreeStartToHandsFreeTranscriptionCallback() {
        let (dispatcher, _, mgr) = makeDispatcher()

        var handsFreeTranscriptionFired = false
        dispatcher.onHandsFreeTranscription = { handsFreeTranscriptionFired = true }

        dispatcher.syncBindings()

        // Simulate HotkeyManager firing onHandsFreeStart directly (state machine
        // path tested in HotkeyManagerTests; here we verify wiring only).
        mgr.onHandsFreeStart?()

        XCTAssertTrue(handsFreeTranscriptionFired,
            "Firing HotkeyManager.onHandsFreeStart must invoke dispatcher.onHandsFreeTranscription")
    }

    func testHandsFreeTranscriptionCallbackNotFiredWhenNotSet() {
        let (dispatcher, _, mgr) = makeDispatcher()
        dispatcher.onHandsFreeTranscription = nil
        dispatcher.syncBindings()
        // Should not crash when callback is nil.
        mgr.onHandsFreeStart?()
    }

    func testSyncBindingsRewiresHandsFreeStartOnSecondCall() {
        let (dispatcher, _, mgr) = makeDispatcher()

        var firstCallbackFired = false
        var secondCallbackFired = false

        dispatcher.onHandsFreeTranscription = { firstCallbackFired = true }
        dispatcher.syncBindings()

        // Replace callback and re-sync.
        dispatcher.onHandsFreeTranscription = { secondCallbackFired = true }
        dispatcher.syncBindings()

        mgr.onHandsFreeStart?()

        XCTAssertFalse(firstCallbackFired,
            "Old handsFreeTranscription callback must not fire after re-sync")
        XCTAssertTrue(secondCallbackFired,
            "New handsFreeTranscription callback must fire after re-sync")
    }

    // MARK: - updateBinding

    func testUpdateBindingReSyncsWatchedKeyCode() {
        let (dispatcher, store, mgr) = makeDispatcher()
        dispatcher.syncBindings()

        // Change the binding externally (as SettingsView does via HotkeyBindingStore).
        let newKeyCode: CGKeyCode = 0x61 // F6
        store.setBinding(HotkeyBinding(action: .defaultTranscription, keyCode: newKeyCode))

        dispatcher.updateBinding(HotkeyBinding(action: .defaultTranscription, keyCode: newKeyCode))

        XCTAssertEqual(mgr.watchedKeyCode, newKeyCode,
            "updateBinding must cause dispatcher to re-sync and update watchedKeyCode")
    }

    func testUpdateBindingForNonPrimaryActionDoesNotCorruptWatchedKeyCode() {
        let (dispatcher, store, mgr) = makeDispatcher()
        store.setBinding(HotkeyBinding(action: .defaultTranscription, keyCode: CGKeyCode(0x3D)))
        dispatcher.syncBindings()

        // Update a secondary binding — must not disturb watchedKeyCode.
        let popoverBinding = HotkeyBinding(action: .openPopover, keyCode: CGKeyCode(0x61))
        store.setBinding(popoverBinding)
        dispatcher.updateBinding(popoverBinding)

        XCTAssertEqual(mgr.watchedKeyCode, CGKeyCode(0x3D),
            "Updating a non-primary binding must not change watchedKeyCode")
    }

    // MARK: - Callback assignment (openPopover, injectLastTranscription)

    func testOpenPopoverCallbackCanBeAssignedAndCleared() {
        let (dispatcher, _, _) = makeDispatcher()
        var fired = false
        dispatcher.onOpenPopover = { fired = true }
        dispatcher.onOpenPopover?()
        XCTAssertTrue(fired)

        dispatcher.onOpenPopover = nil
        XCTAssertNil(dispatcher.onOpenPopover)
    }

    func testInjectLastTranscriptionCallbackCanBeAssignedAndCleared() {
        let (dispatcher, _, _) = makeDispatcher()
        var fired = false
        dispatcher.onInjectLastTranscription = { fired = true }
        dispatcher.onInjectLastTranscription?()
        XCTAssertTrue(fired)

        dispatcher.onInjectLastTranscription = nil
        XCTAssertNil(dispatcher.onInjectLastTranscription)
    }

    func testDefaultTranscriptionCallbackCanBeAssignedAndCleared() {
        let (dispatcher, _, _) = makeDispatcher()
        var fired = false
        dispatcher.onDefaultTranscription = { fired = true }
        dispatcher.onDefaultTranscription?()
        XCTAssertTrue(fired)

        dispatcher.onDefaultTranscription = nil
        XCTAssertNil(dispatcher.onDefaultTranscription)
    }

    // MARK: - Secondary tap (hardware-only)

    // Disabled: secondary CGEventTap requires Input Monitoring permission which
    // cannot be granted in the test sandbox.
    // MANUAL TEST: configure openPopover binding (e.g. F6) and injectLastTranscription
    // (e.g. F7) in Settings → Hotkeys.  Press F6 → confirm popover toggles.  Press F7
    // → confirm last transcription text is re-injected into the active field.
    func testSecondaryTapFiresOpenPopoverAndInjectCallbacks() throws {
        throw XCTSkip(
            "Requires Input Monitoring permission — run manually on device. " +
            "Bind openPopover to F6, injectLastTranscription to F7, launch the app, " +
            "press each key, and verify the corresponding action fires."
        )
    }
}
