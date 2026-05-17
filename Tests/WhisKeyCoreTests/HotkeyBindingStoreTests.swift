@testable import WhisKeyCore
import CoreGraphics
import XCTest

// MARK: - HotkeyBindingStore Tests (S3-T6)
//
// Tests run against an isolated UserDefaults suite so they never pollute
// the host application's standard defaults.

// `HotkeyBindingStore` is @MainActor-isolated; annotating the test class
// ensures all test methods run on the main actor without async wrapping.
@MainActor
final class HotkeyBindingStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var store: HotkeyBindingStore!

    override func setUp() {
        super.setUp()
        // Fresh suite per test — no cross-test pollution.
        let suiteName = "com.whiskey.test.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        store = HotkeyBindingStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removeSuite(named: defaults.description)
        store = nil
        defaults = nil
        super.tearDown()
    }

    // MARK: - Default binding

    func testDefaultBindingIsRightOptionForDefaultTranscription() {
        let binding = store.binding(for: .defaultTranscription)
        XCTAssertEqual(binding.keyCode, CGKeyCode(0x3D), "Default keyCode must be Right Option (0x3D)")
        XCTAssertNil(binding.modifierFlags, "Default Right Option binding has no modifier flags")
    }

    func testOtherActionsDefaultToNotSet() {
        for action in HotkeyAction.allCases where action != .defaultTranscription {
            let binding = store.binding(for: action)
            XCTAssertNil(binding.keyCode, "\(action.rawValue) should default to not set")
        }
    }

    func testDefaultTranscriptionDisplayStringIsRightOpt() {
        let binding = store.binding(for: .defaultTranscription)
        XCTAssertEqual(binding.displayString, "⌥ (Right Opt)")
    }

    // MARK: - setBinding persists and round-trips

    func testSetBindingPersistsToUserDefaults() {
        let binding = HotkeyBinding(
            action: .openPopover,
            keyCode: CGKeyCode(0x23), // P
            modifierFlags: [.maskControl, .maskAlternate]
        )
        store.setBinding(binding)

        // Re-create store from same defaults to verify round-trip.
        let store2 = HotkeyBindingStore(defaults: defaults)
        let loaded = store2.binding(for: .openPopover)
        XCTAssertEqual(loaded.keyCode, binding.keyCode)
        XCTAssertEqual(loaded.modifierFlags, binding.modifierFlags)
    }

    func testSetBindingUpdatesInMemoryCache() {
        let binding = HotkeyBinding(
            action: .handsFreeTranscription,
            keyCode: CGKeyCode(0x20), // U
            modifierFlags: .maskCommand
        )
        store.setBinding(binding)
        let result = store.binding(for: .handsFreeTranscription)
        XCTAssertEqual(result.keyCode, CGKeyCode(0x20))
    }

    func testSetBindingOverwritesPreviousBinding() {
        let first = HotkeyBinding(action: .openPopover, keyCode: CGKeyCode(0x00), modifierFlags: nil)
        store.setBinding(first)
        let second = HotkeyBinding(action: .openPopover, keyCode: CGKeyCode(0x23), modifierFlags: .maskControl)
        store.setBinding(second)
        XCTAssertEqual(store.binding(for: .openPopover).keyCode, CGKeyCode(0x23))
    }

    // MARK: - clearBinding

    func testClearBindingSetsKeyCodeToNil() {
        let binding = HotkeyBinding(action: .openPopover, keyCode: CGKeyCode(0x23), modifierFlags: nil)
        store.setBinding(binding)
        store.clearBinding(for: .openPopover)
        XCTAssertNil(store.binding(for: .openPopover).keyCode)
    }

    func testClearBindingPersists() {
        store.setBinding(HotkeyBinding(action: .openPopover, keyCode: CGKeyCode(0x23), modifierFlags: nil))
        store.clearBinding(for: .openPopover)

        let store2 = HotkeyBindingStore(defaults: defaults)
        XCTAssertNil(store2.binding(for: .openPopover).keyCode)
    }

    func testClearDefaultTranscriptionRemovesBinding() {
        store.clearBinding(for: .defaultTranscription)
        XCTAssertNil(store.binding(for: .defaultTranscription).keyCode)
    }

    // MARK: - Conflict detection

    func testConflictingActionReturnsOwningAction() {
        let binding = HotkeyBinding(
            action: .openPopover,
            keyCode: CGKeyCode(0x23), // P
            modifierFlags: .maskControl
        )
        store.setBinding(binding)

        let conflict = store.conflictingAction(
            for: CGKeyCode(0x23),
            modifierFlags: .maskControl,
            excluding: nil
        )
        XCTAssertEqual(conflict, .openPopover)
    }

    func testNoConflictWhenExcludingSameAction() {
        let binding = HotkeyBinding(
            action: .openPopover,
            keyCode: CGKeyCode(0x23),
            modifierFlags: .maskControl
        )
        store.setBinding(binding)

        let conflict = store.conflictingAction(
            for: CGKeyCode(0x23),
            modifierFlags: .maskControl,
            excluding: .openPopover
        )
        XCTAssertNil(conflict, "Excluding the owning action must not return a conflict")
    }

    func testNoConflictOnDifferentKeyCode() {
        store.setBinding(HotkeyBinding(
            action: .openPopover,
            keyCode: CGKeyCode(0x23),
            modifierFlags: nil
        ))
        let conflict = store.conflictingAction(
            for: CGKeyCode(0x00), // A — different key
            modifierFlags: nil,
            excluding: nil
        )
        XCTAssertNil(conflict)
    }

    func testNoConflictOnDifferentModifiers() {
        store.setBinding(HotkeyBinding(
            action: .openPopover,
            keyCode: CGKeyCode(0x23),
            modifierFlags: .maskControl
        ))
        let conflict = store.conflictingAction(
            for: CGKeyCode(0x23),
            modifierFlags: .maskCommand, // Different modifier
            excluding: nil
        )
        XCTAssertNil(conflict)
    }

    func testDefaultTranscriptionConflictsWithRightOption() {
        // Right Option is the default; recording the same combo for another action should conflict.
        let conflict = store.conflictingAction(
            for: CGKeyCode(0x3D),
            modifierFlags: nil,
            excluding: nil
        )
        XCTAssertEqual(conflict, .defaultTranscription)
    }

    func testDefaultTranscriptionExcludedFromOwnConflictCheck() {
        let conflict = store.conflictingAction(
            for: CGKeyCode(0x3D),
            modifierFlags: nil,
            excluding: .defaultTranscription
        )
        XCTAssertNil(conflict)
    }

    // MARK: - Reserved combo detection

    func testCmdQIsReserved() {
        // ⌘Q: keyCode 0x0C, modifier .maskCommand
        XCTAssertTrue(store.isReserved(keyCode: CGKeyCode(0x0C), modifierFlags: .maskCommand))
    }

    func testUnboundComboIsNotReserved() {
        // ⌃⌥P is not in the reserved list.
        XCTAssertFalse(
            store.isReserved(
                keyCode: CGKeyCode(0x23),
                modifierFlags: [.maskControl, .maskAlternate]
            )
        )
    }

    // MARK: - Migration idempotency

    func testMigrationIsIdempotentOnSecondInit() {
        // First init seeds defaults.
        let binding1 = store.binding(for: .defaultTranscription)

        // Second init from same defaults should not change the binding.
        let store2 = HotkeyBindingStore(defaults: defaults)
        let binding2 = store2.binding(for: .defaultTranscription)

        XCTAssertEqual(binding1.keyCode, binding2.keyCode)
    }
}
