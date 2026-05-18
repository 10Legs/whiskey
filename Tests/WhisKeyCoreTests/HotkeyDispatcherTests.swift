import CoreGraphics
@testable import WhisKeyCore
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

/// Groups the three objects produced by `makeDispatcher()`.
private struct DispatcherFixture {
    let dispatcher: HotkeyDispatcher
    let store: HotkeyBindingStore
    let manager: HotkeyManager
}

@MainActor
class HotkeyDispatcherTests: XCTestCase {

    // MARK: - Helpers

    /// Returns a fresh store backed by an in-memory UserDefaults suite.
    private func makeStore(suite: String = UUID().uuidString) throws -> HotkeyBindingStore {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        return HotkeyBindingStore(defaults: defaults)
    }

    private func makeDispatcher(
        store: HotkeyBindingStore? = nil
    ) throws -> DispatcherFixture {
        let bindingStore = try store ?? makeStore()
        let mgr = HotkeyManager()
        let dispatcher = HotkeyDispatcher(bindingStore: bindingStore, hotkeyManager: mgr)
        return DispatcherFixture(dispatcher: dispatcher, store: bindingStore, manager: mgr)
    }

    // MARK: - syncBindings: defaultTranscription → watchedKeyCode

    func testSyncBindingsPushesDefaultTranscriptionKeyCode() throws {
        let fixture = try makeDispatcher()

        let customKeyCode: CGKeyCode = 0x60 // F5
        fixture.store.setBinding(HotkeyBinding(action: .defaultTranscription, keyCode: customKeyCode))

        fixture.dispatcher.syncBindings()

        XCTAssertEqual(fixture.manager.watchedKeyCode, customKeyCode,
            "syncBindings must push defaultTranscription keyCode into HotkeyManager.watchedKeyCode")
    }

    func testSyncBindingsUsesDefaultKeyCodeWhenNoCustomBinding() throws {
        let fixture = try makeDispatcher()
        fixture.dispatcher.syncBindings()
        // Default is Right Option (0x3D) seeded by HotkeyBindingStore.
        XCTAssertEqual(fixture.manager.watchedKeyCode, CGKeyCode(0x3D),
            "watchedKeyCode must equal the default Right Option key code when no custom binding is set")
    }

    func testSyncBindingsWithNilKeyCodeLeavesWatchedKeyCodeUnchanged() throws {
        let fixture = try makeDispatcher()
        // Seed a known value first.
        fixture.manager.watchedKeyCode = 0x3D
        // Clear the default binding so keyCode is nil.
        fixture.store.clearBinding(for: .defaultTranscription)

        fixture.dispatcher.syncBindings()

        // watchedKeyCode should remain 0x3D — no update when keyCode is nil.
        XCTAssertEqual(fixture.manager.watchedKeyCode, CGKeyCode(0x3D),
            "watchedKeyCode must not change when defaultTranscription binding has no keyCode")
    }

    // MARK: - syncBindings: handsFreeTranscription callback wiring

    func testSyncBindingsWiresHandsFreeStartToHandsFreeTranscriptionCallback() throws {
        let fixture = try makeDispatcher()

        var handsFreeTranscriptionFired = false
        fixture.dispatcher.onHandsFreeTranscription = { handsFreeTranscriptionFired = true }

        fixture.dispatcher.syncBindings()

        // Simulate HotkeyManager firing onHandsFreeStart directly (state machine
        // path tested in HotkeyManagerTests; here we verify wiring only).
        fixture.manager.onHandsFreeStart?()

        XCTAssertTrue(handsFreeTranscriptionFired,
            "Firing HotkeyManager.onHandsFreeStart must invoke dispatcher.onHandsFreeTranscription")
    }

    func testHandsFreeTranscriptionCallbackNotFiredWhenNotSet() throws {
        let fixture = try makeDispatcher()
        fixture.dispatcher.onHandsFreeTranscription = nil
        fixture.dispatcher.syncBindings()
        // Should not crash when callback is nil.
        fixture.manager.onHandsFreeStart?()
    }

    func testSyncBindingsRewiresHandsFreeStartOnSecondCall() throws {
        let fixture = try makeDispatcher()

        var firstCallbackFired = false
        var secondCallbackFired = false

        fixture.dispatcher.onHandsFreeTranscription = { firstCallbackFired = true }
        fixture.dispatcher.syncBindings()

        // Replace callback and re-sync.
        fixture.dispatcher.onHandsFreeTranscription = { secondCallbackFired = true }
        fixture.dispatcher.syncBindings()

        fixture.manager.onHandsFreeStart?()

        XCTAssertFalse(firstCallbackFired,
            "Old handsFreeTranscription callback must not fire after re-sync")
        XCTAssertTrue(secondCallbackFired,
            "New handsFreeTranscription callback must fire after re-sync")
    }

    // MARK: - updateBinding

    func testUpdateBindingReSyncsWatchedKeyCode() throws {
        let fixture = try makeDispatcher()
        fixture.dispatcher.syncBindings()

        // Change the binding externally (as SettingsView does via HotkeyBindingStore).
        let newKeyCode: CGKeyCode = 0x61 // F6
        fixture.store.setBinding(HotkeyBinding(action: .defaultTranscription, keyCode: newKeyCode))

        fixture.dispatcher.updateBinding(HotkeyBinding(action: .defaultTranscription, keyCode: newKeyCode))

        XCTAssertEqual(fixture.manager.watchedKeyCode, newKeyCode,
            "updateBinding must cause dispatcher to re-sync and update watchedKeyCode")
    }

    func testUpdateBindingForNonPrimaryActionDoesNotCorruptWatchedKeyCode() throws {
        let fixture = try makeDispatcher()
        fixture.store.setBinding(HotkeyBinding(action: .defaultTranscription, keyCode: CGKeyCode(0x3D)))
        fixture.dispatcher.syncBindings()

        // Update a secondary binding — must not disturb watchedKeyCode.
        let popoverBinding = HotkeyBinding(action: .openPopover, keyCode: CGKeyCode(0x61))
        fixture.store.setBinding(popoverBinding)
        fixture.dispatcher.updateBinding(popoverBinding)

        XCTAssertEqual(fixture.manager.watchedKeyCode, CGKeyCode(0x3D),
            "Updating a non-primary binding must not change watchedKeyCode")
    }

    // MARK: - Callback assignment (openPopover, injectLastTranscription)

    func testOpenPopoverCallbackCanBeAssignedAndCleared() throws {
        let fixture = try makeDispatcher()
        var fired = false
        fixture.dispatcher.onOpenPopover = { fired = true }
        fixture.dispatcher.onOpenPopover?()
        XCTAssertTrue(fired)

        fixture.dispatcher.onOpenPopover = nil
        XCTAssertNil(fixture.dispatcher.onOpenPopover)
    }

    func testInjectLastTranscriptionCallbackCanBeAssignedAndCleared() throws {
        let fixture = try makeDispatcher()
        var fired = false
        fixture.dispatcher.onInjectLastTranscription = { fired = true }
        fixture.dispatcher.onInjectLastTranscription?()
        XCTAssertTrue(fired)

        fixture.dispatcher.onInjectLastTranscription = nil
        XCTAssertNil(fixture.dispatcher.onInjectLastTranscription)
    }

    func testDefaultTranscriptionCallbackCanBeAssignedAndCleared() throws {
        let fixture = try makeDispatcher()
        var fired = false
        fixture.dispatcher.onDefaultTranscription = { fired = true }
        fixture.dispatcher.onDefaultTranscription?()
        XCTAssertTrue(fired)

        fixture.dispatcher.onDefaultTranscription = nil
        XCTAssertNil(fixture.dispatcher.onDefaultTranscription)
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
