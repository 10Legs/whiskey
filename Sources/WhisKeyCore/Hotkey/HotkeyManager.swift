import AppKit
import Carbon

/// Monitors global hotkey events via CGEventTap.
///
/// Default hotkey: Right Option key (kVK_RightOption).
/// Requires Input Monitoring permission.
///
/// Push-to-talk mode: hold key → recording starts; release → recording stops and transcription runs.
/// Toggle mode:       first press → starts; second press → stops.
///
/// ## Rapid re-entry protection
///
/// `flagsChanged` and `keyDown` for the same modifier key can be reported by macOS
/// in rapid succession (observed: two `keyDown` events ~4 ms apart). Without a
/// debounce, this caused `AudioCaptureService.startCapture()` to be invoked twice,
/// raising "already in progress" and propagating an error to the UI layer.
///
/// `HotkeyManager` enforces:
///   - Strict `isRecording` state transitions (existing).
///   - A per-edge debounce window (`minEdgeIntervalMillis`) that drops any
///     down → down or up → up transitions occurring within the window.
public final class HotkeyManager: @unchecked Sendable {

    // MARK: - Mode

    public enum Mode: Sendable {
        /// Hold the hotkey to record; release triggers transcription.
        case pushToTalk
        /// First press starts recording; second press stops.
        case toggle
    }

    // MARK: - Configuration

    public var mode: Mode = .pushToTalk

    /// The virtual key code to watch (default: Right Option = 0x3D).
    public var watchedKeyCode: CGKeyCode = 0x3D

    /// Minimum interval (milliseconds) between two same-edge transitions before
    /// the second one is honoured. Tuned to drop OS-level duplicate events
    /// (typical jitter ≤ 10 ms) while preserving fast push-to-talk taps.
    public var minEdgeIntervalMillis: Double = 50.0

    // MARK: - Callbacks

    public var onStartRecording: (() -> Void)?
    public var onStopRecording: (() -> Void)?

    // MARK: - State

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isRecording = false
    /// Retains `self` for the CGEventTap callback; released in `stop()`.
    private var retainedSelf: Unmanaged<HotkeyManager>?

    /// Mach absolute time (ms since boot, monotonic) of the last accepted
    /// start/stop transition. Used to debounce duplicate OS events.
    private var lastStartEdgeMillis: Double = -Double.infinity
    private var lastStopEdgeMillis: Double = -Double.infinity

    public init() {}

    // MARK: - Public API

    /// Install the CGEventTap and begin listening for hotkey events.
    /// Returns false if the tap could not be created (Input Monitoring not granted).
    @discardableResult
    public func start() -> Bool {
        let eventsOfInterest: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue)      |
            (1 << CGEventType.keyUp.rawValue)

        let retained = Unmanaged.passRetained(self)
        let selfPtr = retained.toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventsOfInterest,
            callback: hotkeyEventCallback,
            userInfo: selfPtr
        ) else {
            // Tap creation failed — Input Monitoring permission not granted.
            retained.release()
            return false
        }

        retainedSelf = retained
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    /// Disable and remove the event tap.
    public func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        // Balance the passRetained() from start().
        retainedSelf?.release()
        retainedSelf = nil
    }

    // MARK: - Internal event handling

    fileprivate func handleEvent(_ event: CGEvent) {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let type = event.type

        switch mode {
        case .pushToTalk:
            handlePushToTalk(event: event, type: type, keyCode: keyCode)
        case .toggle:
            handleToggle(event: event, type: type, keyCode: keyCode)
        }
    }

    /// Monotonic millisecond timestamp suitable for debounce arithmetic.
    private func nowMillis() -> Double {
        // ProcessInfo.systemUptime is documented monotonic since boot and is
        // unaffected by wall-clock adjustments.
        return ProcessInfo.processInfo.systemUptime * 1000.0
    }

    /// Returns true if the start edge should fire (and records the timestamp);
    /// false if it falls inside the debounce window.
    private func acceptStartEdge() -> Bool {
        let now = nowMillis()
        guard now - lastStartEdgeMillis >= minEdgeIntervalMillis else {
            return false
        }
        lastStartEdgeMillis = now
        return true
    }

    private func acceptStopEdge() -> Bool {
        let now = nowMillis()
        guard now - lastStopEdgeMillis >= minEdgeIntervalMillis else {
            return false
        }
        lastStopEdgeMillis = now
        return true
    }

    private func handlePushToTalk(event: CGEvent, type: CGEventType, keyCode: CGKeyCode) {
        if type == .flagsChanged {
            // For modifier keys (Option, Command, etc.), flagsChanged fires on both
            // press and release. Distinguish by checking if the flag is now set.
            let flags = event.flags
            let optionDown = flags.contains(.maskAlternate)

            if keyCode == watchedKeyCode {
                if optionDown && !isRecording {
                    guard acceptStartEdge() else { return }
                    isRecording = true
                    onStartRecording?()
                } else if !optionDown && isRecording {
                    guard acceptStopEdge() else { return }
                    isRecording = false
                    onStopRecording?()
                }
            }
        } else if type == .keyDown && keyCode == watchedKeyCode && !isRecording {
            guard acceptStartEdge() else { return }
            isRecording = true
            onStartRecording?()
        } else if type == .keyUp && keyCode == watchedKeyCode && isRecording {
            guard acceptStopEdge() else { return }
            isRecording = false
            onStopRecording?()
        }
    }

    private func handleToggle(event: CGEvent, type: CGEventType, keyCode: CGKeyCode) {
        guard type == .keyDown && keyCode == watchedKeyCode else { return }
        if isRecording {
            guard acceptStopEdge() else { return }
            isRecording = false
            onStopRecording?()
        } else {
            guard acceptStartEdge() else { return }
            isRecording = true
            onStartRecording?()
        }
    }
}

// MARK: - C callback (must be a free function)

private func hotkeyEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let ptr = userInfo else { return Unmanaged.passUnretained(event) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(ptr).takeUnretainedValue()
    manager.handleEvent(event)
    return Unmanaged.passUnretained(event)
}
