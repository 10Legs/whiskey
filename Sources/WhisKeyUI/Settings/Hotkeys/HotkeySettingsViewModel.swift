import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import WhisKeyCore

// MARK: - Row Recording State

/// State for a single hotkey row's recording session.
enum RowRecordingState: Sendable {
    case idle
    case recording
    case conflict(comboString: String, message: String)
    case confirmed
}

// MARK: - HotkeySettingsViewModel

/// View model for `HotkeySettingsView`.
///
/// Owns the `NSEvent` local monitor that captures the next key press during recording.
/// The monitor is installed only while a row is in recording mode, and is torn down
/// immediately on cancel, conflict acceptance, or confirmation.
@MainActor
final class HotkeySettingsViewModel: ObservableObject {

    // MARK: - Published state

    @Published private(set) var recordingAction: HotkeyAction?
    @Published private(set) var rowStates: [HotkeyAction: RowRecordingState] = [:]
    @Published private(set) var confirmationTimerActions: Set<HotkeyAction> = []

    // MARK: - Dependencies

    let store: HotkeyBindingStore

    // MARK: - Private

    private var eventMonitor: Any?
    private var confirmationTasks: [HotkeyAction: Task<Void, Never>] = [:]

    init(store: HotkeyBindingStore) {
        self.store = store
        for action in HotkeyAction.allCases {
            rowStates[action] = .idle
        }
    }

    // MARK: - Computed helpers

    func binding(for action: HotkeyAction) -> HotkeyBinding {
        store.binding(for: action)
    }

    var isAnyRowRecording: Bool { recordingAction != nil }

    func rowState(for action: HotkeyAction) -> RowRecordingState {
        rowStates[action] ?? .idle
    }

    // MARK: - Record / Cancel

    func startRecording(action: HotkeyAction) {
        guard recordingAction == nil else { return }
        recordingAction = action
        rowStates[action] = .recording
        installMonitor(for: action)
    }

    func cancelRecording(action: HotkeyAction) {
        guard recordingAction == action else { return }
        tearDownMonitor()
        recordingAction = nil
        rowStates[action] = .idle
    }

    func clearBinding(action: HotkeyAction) {
        store.clearBinding(for: action)
        rowStates[action] = .idle
        objectWillChange.send()
    }

    // MARK: - Event monitor

    private func installMonitor(for action: HotkeyAction) {
        // Listen for all key events. NSEvent.addLocalMonitorForEvents does not
        // intercept events delivered to other apps; for a settings window that's fine —
        // the window must be key for this to work, which it will be when the user
        // clicks Record.
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .flagsChanged]
        ) { [weak self] event in
            guard let self else { return event }
            self.handleCapturedEvent(event, action: action)
            // Consume the event so it doesn't propagate to menu items etc.
            return nil
        }
    }

    private func tearDownMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    // swiftlint:disable:next function_body_length
    private func handleCapturedEvent(_ event: NSEvent, action: HotkeyAction) {
        // Escape → cancel recording.
        if event.type == .keyDown && event.keyCode == 0x35 {
            cancelRecording(action: action)
            return
        }

        // Bare modifier-only presses (flagsChanged without a non-modifier key)
        // are treated as reserved / invalid unless it's a solo function-modifier key.
        // For simplicity we allow flagsChanged only for dedicated modifier keys
        // that act as hotkeys by themselves (e.g. Right Option = 0x3D).
        let keyCode = CGKeyCode(event.keyCode)
        let modifiers = cgEventFlags(from: event.modifierFlags)

        if event.type == .flagsChanged {
            // Only allow solo modifier keys that are commonly used as standalone hotkeys.
            // Right Option (0x3D) is the canonical example.
            let allowedSoloModifiers: Set<CGKeyCode> = [0x3D, 0x3A, 0x38, 0x3C, 0x36, 0x3B, 0x3E]
            guard allowedSoloModifiers.contains(keyCode) else { return }
            // A flagsChanged DOWN is when the modifier bit IS set; flagsChanged UP is when cleared.
            // We only want the DOWN transition.
            guard event.modifierFlags.intersection([.option, .command, .control, .shift]) != [] ||
                  keyCode == 0x3D || keyCode == 0x3A else { return }
        }

        // Check macOS reserved combos.
        if store.isReserved(keyCode: keyCode, modifierFlags: modifiers.isEmpty ? nil : modifiers) {
            let comboString = comboDisplayString(keyCode: keyCode, modifiers: modifiers)
            rowStates[action] = .conflict(
                comboString: comboString,
                message: "\(comboString) is reserved by macOS"
            )
            return
        }

        // Check bare modifier-only combos (bare ⌘, bare ⌃ etc. without a non-modifier key).
        if event.type == .keyDown {
            let nonModifierMask: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
            let hasNonModifierKey = true // Any keyDown event has a non-modifier key component.
            _ = hasNonModifierKey // keyDown guarantees non-modifier key, this check is satisfied.

            // Block: modifier-only combos where the key itself is a modifier (bare Cmd, bare Ctrl).
            let bareModifierKeys: Set<CGKeyCode> = [0x38, 0x3C, 0x36, 0x3B, 0x3E]
            if bareModifierKeys.contains(keyCode) && event.modifierFlags.intersection(nonModifierMask) == [] {
                let comboString = comboDisplayString(keyCode: keyCode, modifiers: modifiers)
                rowStates[action] = .conflict(
                    comboString: comboString,
                    message: "\(comboString) is reserved by macOS"
                )
                return
            }
        }

        // Intra-app conflict detection.
        let effectiveModifiers: CGEventFlags? = modifiers.isEmpty ? nil : modifiers
        if let conflicting = store.conflictingAction(
            for: keyCode,
            modifierFlags: effectiveModifiers,
            excluding: action
        ) {
            let comboString = comboDisplayString(keyCode: keyCode, modifiers: modifiers)
            rowStates[action] = .conflict(
                comboString: comboString,
                message: "\(comboString) is already used by \(conflicting.displayName)"
            )
            return
        }

        // Valid combo — save and confirm.
        let newBinding = HotkeyBinding(
            action: action,
            keyCode: keyCode,
            modifierFlags: effectiveModifiers
        )
        store.setBinding(newBinding)
        tearDownMonitor()
        recordingAction = nil
        rowStates[action] = .confirmed
        scheduleConfirmationDismissal(for: action)
    }

    private func scheduleConfirmationDismissal(for action: HotkeyAction) {
        confirmationTasks[action]?.cancel()
        confirmationTasks[action] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                // Only clear confirmed state — do not overwrite a subsequent recording.
                if case .confirmed = self.rowStates[action] {
                    self.rowStates[action] = .idle
                }
            }
        }
    }

    // MARK: - Display helpers

    func comboDisplayString(keyCode: CGKeyCode, modifiers: CGEventFlags) -> String {
        let tempBinding = HotkeyBinding(
            action: .defaultTranscription,
            keyCode: keyCode,
            modifierFlags: modifiers.isEmpty ? nil : modifiers
        )
        return tempBinding.displayString
    }

    private func cgEventFlags(from nsFlags: NSEvent.ModifierFlags) -> CGEventFlags {
        var flags = CGEventFlags()
        if nsFlags.contains(.control) { flags.insert(.maskControl) }
        if nsFlags.contains(.option)  { flags.insert(.maskAlternate) }
        if nsFlags.contains(.shift)   { flags.insert(.maskShift) }
        if nsFlags.contains(.command) { flags.insert(.maskCommand) }
        return flags
    }
}
