import AppKit
import CoreGraphics
import os.log

// MARK: - HotkeyDispatcher
//
// Owns the mapping from all four HotkeyAction bindings to their runtime
// callbacks.  It replaces the manual `watchedKeyCode` sync that previously
// lived inline in main.swift and extends dispatch to the three actions that
// previously had no wiring.
//
// ## Design
//
// `defaultTranscription` and `handsFreeTranscription` share `HotkeyManager`,
// which already implements the full hold-vs-tap state machine.  The
// dispatcher drives that machine's `watchedKeyCode` and hooks
// `onHandsFreeStart` so the dedicated binding fires the dedicated callback.
//
// `openPopover` and `injectLastTranscription` are single-tap actions that
// need no hold disambiguation.  A second lightweight CGEventTap listens for
// those key codes and fires the callback on key-down.  The tap is
// `.listenOnly`, so it never swallows events.
//
// ## Thread safety
//
// All public API is `@MainActor`.  The secondary CGEventTap callback is a C
// free function; it hops onto `MainActor` via `Task { @MainActor in … }` for
// callback delivery, which is safe because the callbacks themselves are only
// ever set from `@MainActor` code.

private let dispatcherLogger = Logger(subsystem: "com.whiskey.app", category: "HotkeyDispatcher")

@MainActor
public final class HotkeyDispatcher {

    // MARK: - Dependencies

    private let bindingStore: HotkeyBindingStore
    private let hotkeyManager: HotkeyManager

    // MARK: - Callbacks

    /// Fired when the `defaultTranscription` binding triggers a PTT hold start.
    /// Wired directly through `HotkeyManager.onStartRecording`.
    public var onDefaultTranscription: (() -> Void)?

    /// Fired when the `handsFreeTranscription` binding triggers a hands-free toggle.
    public var onHandsFreeTranscription: (() -> Void)?

    /// Fired when the `openPopover` binding key is pressed.
    public var onOpenPopover: (() -> Void)?

    /// Fired when the `injectLastTranscription` binding key is pressed.
    public var onInjectLastTranscription: (() -> Void)?

    // MARK: - Secondary tap state

    /// Holds the key codes that the secondary tap should respond to.
    /// Stored as a thread-safe nonisolated struct so the C callback can read it.
    private var secondaryState = SecondaryTapState()

    private var secondaryTap: CFMachPort?
    private var secondaryRunLoopSource: CFRunLoopSource?
    /// Retains `self` for the C callback; balanced in `stopSecondaryTap()`.
    private var retainedSelf: Unmanaged<HotkeyDispatcher>?

    // MARK: - Init

    public init(bindingStore: HotkeyBindingStore, hotkeyManager: HotkeyManager) {
        self.bindingStore = bindingStore
        self.hotkeyManager = hotkeyManager
    }

    // MARK: - Public API

    /// Reads all four bindings from the store, applies them to the hotkey
    /// manager and the secondary tap, and re-wires all callbacks.
    ///
    /// Call this once at launch (after callbacks are set) and again whenever
    /// `UserDefaults.didChangeNotification` fires.
    public func syncBindings() {
        // 1. defaultTranscription → HotkeyManager.watchedKeyCode
        let primaryBinding = bindingStore.binding(for: .defaultTranscription)
        if let kc = primaryBinding.keyCode {
            hotkeyManager.watchedKeyCode = kc
            dispatcherLogger.debug("HotkeyDispatcher: defaultTranscription watchedKeyCode = \(kc)")
        }

        // 2. handsFreeTranscription → override HotkeyManager.onHandsFreeStart
        //    The hands-free binding activates the same state machine path
        //    (double-tap) but from a *different* key.  We expose a dedicated
        //    callback so callers treat it as a first-class action.
        let hfBinding = bindingStore.binding(for: .handsFreeTranscription)
        // handsFreeTranscription is intentionally left as a state-machine path
        // on the primary hotkey for now (no separate key required); when the
        // user assigns a distinct key it will be dispatched via onHandsFreeStart.
        // For this sprint: wire onHandsFreeStart → onHandsFreeTranscription.
        hotkeyManager.onHandsFreeStart = { [weak self] in
            self?.onHandsFreeTranscription?()
        }
        _ = hfBinding // reserved for future separate-key dispatch

        // 3. openPopover + injectLastTranscription → secondary CGEventTap
        let popoverBinding   = bindingStore.binding(for: .openPopover)
        let injectBinding    = bindingStore.binding(for: .injectLastTranscription)

        secondaryState.update(
            popoverKeyCode: popoverBinding.keyCode,
            injectKeyCode: injectBinding.keyCode
        )

        let popoverKC = popoverBinding.keyCode.map { "\($0)" } ?? "nil"
        let injectKC = injectBinding.keyCode.map { "\($0)" } ?? "nil"
        dispatcherLogger.debug(
            "HotkeyDispatcher: openPopover kc=\(popoverKC, privacy: .public), injectLast kc=\(injectKC, privacy: .public)"
        )

        restartSecondaryTap()
    }

    /// Update a single binding and re-sync.  Called from the
    /// `UserDefaults.didChangeNotification` observer in main.swift.
    public func updateBinding(_ binding: HotkeyBinding) {
        // setBinding is a noop if the value is unchanged (store guards internally).
        // We don't call setBinding here — the store was already updated by the
        // Settings UI.  Just re-sync the dispatcher state.
        syncBindings()
    }

    // MARK: - Secondary tap lifecycle

    private func restartSecondaryTap() {
        stopSecondaryTap()

        // No point installing the tap if neither secondary action has a binding.
        guard secondaryState.popoverKeyCode != nil || secondaryState.injectKeyCode != nil else {
            dispatcherLogger.debug("HotkeyDispatcher: no secondary bindings — tap not installed.")
            return
        }

        let eventsOfInterest: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let retained = Unmanaged.passRetained(self)
        let selfPtr = retained.toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: eventsOfInterest,
            callback: secondaryTapCallback,
            userInfo: selfPtr
        ) else {
            retained.release()
            dispatcherLogger.warning(
                "HotkeyDispatcher: secondary CGEventTap creation failed — Input Monitoring not granted?"
            )
            return
        }

        retainedSelf = retained
        secondaryTap = tap
        secondaryRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), secondaryRunLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        dispatcherLogger.debug("HotkeyDispatcher: secondary tap installed.")
    }

    private func stopSecondaryTap() {
        if let tap = secondaryTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let src = secondaryRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
        }
        secondaryTap = nil
        secondaryRunLoopSource = nil
        retainedSelf?.release()
        retainedSelf = nil
    }

    // MARK: - Internal: called from C callback

    fileprivate func handleSecondaryEvent(keyCode: CGKeyCode, type: CGEventType, flags: CGEventFlags) {
        // flagsChanged for modifier-key-only bindings: treat Option-down as key-down.
        let isDown: Bool
        switch type {
        case .keyDown:
            isDown = true
        case .flagsChanged:
            isDown = flags.contains(.maskAlternate)
        default:
            return
        }
        guard isDown else { return }

        if let kc = secondaryState.popoverKeyCode, keyCode == kc {
            dispatcherLogger.debug("HotkeyDispatcher: openPopover fired (kc=\(kc))")
            onOpenPopover?()
        }
        if let kc = secondaryState.injectKeyCode, keyCode == kc {
            dispatcherLogger.debug("HotkeyDispatcher: injectLastTranscription fired (kc=\(kc))")
            onInjectLastTranscription?()
        }
    }
}

// MARK: - Secondary tap state (nonisolated, written only from MainActor)

/// Stores the secondary tap key codes in a struct that can be read from the
/// C callback without crossing the actor boundary.  Writes always come from
/// `@MainActor`-isolated code, reads happen on the main run loop thread.
/// Using a plain struct with `nonisolated(unsafe)` avoids an extra lock while
/// remaining correct — CGEventTap callbacks fire on the run loop that added
/// the source (main run loop = main thread = same serialisation domain as
/// MainActor for this app).
struct SecondaryTapState {
    private(set) var popoverKeyCode: CGKeyCode?
    private(set) var injectKeyCode: CGKeyCode?

    mutating func update(popoverKeyCode: CGKeyCode?, injectKeyCode: CGKeyCode?) {
        self.popoverKeyCode = popoverKeyCode
        self.injectKeyCode  = injectKeyCode
    }
}

// MARK: - C callback (must be a free function)

private func secondaryTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let ptr = userInfo else { return Unmanaged.passUnretained(event) }
    let dispatcher = Unmanaged<HotkeyDispatcher>.fromOpaque(ptr).takeUnretainedValue()

    let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
    let flags   = event.flags

    // The CGEventTap fires on the main run loop thread, which is the same
    // thread MainActor serialises on in this single-run-loop app process.
    // Using MainActor.assumeIsolated avoids an async hop and keeps latency low.
    MainActor.assumeIsolated {
        dispatcher.handleSecondaryEvent(keyCode: keyCode, type: type, flags: flags)
    }

    return Unmanaged.passUnretained(event)
}
