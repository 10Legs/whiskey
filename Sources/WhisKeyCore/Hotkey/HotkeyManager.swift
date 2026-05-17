import AppKit
import Carbon

/// Monitors global hotkey events via CGEventTap and disambiguates hold vs. tap gestures.
///
/// Default hotkey: Right Option key (kVK_RightOption).
/// Requires Input Monitoring permission.
///
/// ## Interaction model (S3-T4)
///
/// The mode is inferred dynamically from gesture timing — no configuration required.
///
/// **Push-to-talk (hold):** Press and hold the hotkey for >= disambiguationWindowMs →
/// `onStartRecording` fires. Release → `onStopRecording` fires.
///
/// **Hands-free (double-tap):** Tap (press >= minIntentionalTapMs, release), then
/// press again within disambiguationWindowMs → `onHandsFreeStart` fires. Next valid
/// tap (>= minIntentionalTapMs) → `onHandsFreeStop` fires.
///
/// **Single tap:** A single tap not followed by a second tap within the window is silently discarded.
///
/// **Accidental tap floor:** Any press released in under minIntentionalTapMs (80ms) is dropped.
///
/// ## Rapid re-entry protection
///
/// `flagsChanged` and `keyDown` for the same modifier key can be reported by macOS
/// in rapid succession (observed: two `keyDown` events ~4 ms apart). Without a
/// debounce, this caused `AudioCaptureService.startCapture()` to be invoked twice,
/// raising "already in progress" and propagating an error to the UI layer.
///
/// `HotkeyManager` enforces:
///   - A per-edge debounce window (`minEdgeIntervalMillis`) that drops OS-duplicate events.
///   - A state-machine-level accidental tap floor (`minIntentionalTapMs`) above the debounce layer.
public final class HotkeyManager: @unchecked Sendable {

    // MARK: - Private State Machine

    private enum HotkeyState {
        /// No hotkey activity.
        case idle
        /// Key is currently held; disambiguation timer is running.
        case keyDown(pressStartMs: Double)
        /// First valid tap released; inter-tap timer running to detect double-tap.
        case tapPending
        /// PTT hold confirmed — recording is active.
        case holding
        /// Hands-free recording is active; waiting for the stop tap.
        case handsFreeRecording
        /// A key_down arrived during handsFreeRecording; evaluating press for stop.
        case handsFreeStopKeyDown(pressStartMs: Double)
    }

    // MARK: - Configuration

    /// The virtual key code to watch (default: Right Option = 0x3D).
    public var watchedKeyCode: CGKeyCode = 0x3D

    /// Minimum interval (milliseconds) between two same-edge transitions before
    /// the second one is honoured. Tuned to drop OS-level duplicate events
    /// (typical jitter <= 10 ms) while preserving fast push-to-talk taps.
    public var minEdgeIntervalMillis: Double = 50.0

    /// Disambiguation window in milliseconds. A key held longer than this becomes PTT hold;
    /// a second tap arriving within this window after the first tap release triggers hands-free.
    /// Default: 300ms per S3-C2 spec. Valid range: 200-500ms. Configurable in Settings.
    public var disambiguationWindowMs: Double = 300.0

    /// Minimum press duration (ms) for a keypress to be treated as intentional.
    /// Presses shorter than this are silently discarded as accidental contact.
    /// This constant operates above the OS debounce layer (`minEdgeIntervalMillis`).
    /// Per S3-C2 spec: not user-configurable; exposed as a named constant for future promotion.
    public let minIntentionalTapMs: Double = 80.0

    // MARK: - Callbacks

    /// Fired when PTT hold recording begins (key held > disambiguationWindowMs).
    public var onStartRecording: (() -> Void)?
    /// Fired when PTT hold recording ends (key released from holding state).
    public var onStopRecording: (() -> Void)?
    /// Fired when hands-free recording begins (double-tap confirmed within window).
    public var onHandsFreeStart: (() -> Void)?
    /// Fired when hands-free recording ends (next valid tap while in handsFreeRecording).
    public var onHandsFreeStop: (() -> Void)?

    // MARK: - Internal State

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// Retains `self` for the CGEventTap callback; released in `stop()`.
    private var retainedSelf: Unmanaged<HotkeyManager>?

    /// Current state machine state.
    private var hotkeyState: HotkeyState = .idle

    /// Mach absolute time (ms) of the last accepted start/stop transition, for debounce.
    /// Internal (not private) so @testable test shims can reset the debounce clock.
    var lastStartEdgeMillis: Double = -Double.infinity
    var lastStopEdgeMillis: Double = -Double.infinity

    /// Pending disambiguation or inter-tap timer task. Cancelled on every resolving transition.
    private var pendingTimerTask: Task<Void, Never>?

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
        pendingTimerTask?.cancel()
        pendingTimerTask = nil

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

        if type == .flagsChanged && keyCode == watchedKeyCode {
            // Modifier keys fire flagsChanged on both press and release.
            // Distinguish by checking if the Option flag is now set.
            let optionDown = event.flags.contains(.maskAlternate)
            if optionDown {
                handleKeyDown()
            } else {
                handleKeyUp()
            }
        } else if type == .keyDown && keyCode == watchedKeyCode {
            handleKeyDown()
        } else if type == .keyUp && keyCode == watchedKeyCode {
            handleKeyUp()
        }
    }

    // MARK: - State Machine: key down
    // Internal visibility so @testable import can call from test shims.

    // swiftlint:disable:next function_body_length
    func handleKeyDown() {
        switch hotkeyState {
        case .idle:
            guard acceptStartEdge() else { return }
            hotkeyState = .keyDown(pressStartMs: nowMillis())
            scheduleHoldTimer()

        case .tapPending:
            // Second key_down within the inter-tap window → hands-free.
            guard acceptStartEdge() else { return }
            cancelPendingTimer()
            hotkeyState = .handsFreeRecording
            onHandsFreeStart?()

        case .handsFreeRecording:
            // A tap during hands-free → begin evaluating press for stop gesture.
            guard acceptStartEdge() else { return }
            hotkeyState = .handsFreeStopKeyDown(pressStartMs: nowMillis())

        case .keyDown, .holding, .handsFreeStopKeyDown:
            // Key already down — bounce or re-press during active hold; ignore.
            break
        }
    }

    // MARK: - State Machine: key up

    func handleKeyUp() {
        guard acceptStopEdge() else { return }

        switch hotkeyState {
        case .keyDown(let pressStartMs):
            let duration = nowMillis() - pressStartMs
            cancelPendingTimer()

            if duration < minIntentionalTapMs {
                // Accidental tap — drop silently, back to idle.
                hotkeyState = .idle
            } else {
                // Valid first tap. Enter tapPending and start inter-tap timer.
                hotkeyState = .tapPending
                scheduleInterTapTimer()
            }

        case .holding:
            // PTT release.
            hotkeyState = .idle
            onStopRecording?()

        case .handsFreeStopKeyDown(let pressStartMs):
            let duration = nowMillis() - pressStartMs
            if duration >= minIntentionalTapMs {
                hotkeyState = .idle
                onHandsFreeStop?()
            } else {
                // Too short — drop; remain in hands-free recording.
                hotkeyState = .handsFreeRecording
            }

        case .tapPending, .idle, .handsFreeRecording:
            // Spurious key_up — ignore.
            break
        }
    }

    // MARK: - Timer scheduling

    /// Starts the hold disambiguation timer. If it fires while still in keyDown, transitions to holding.
    private func scheduleHoldTimer() {
        let windowMs = disambiguationWindowMs
        pendingTimerTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(windowMs * 1_000_000))
            guard !Task.isCancelled else { return }
            self.holdTimerFired()
        }
    }

    /// Starts the inter-tap timer. If it fires while still in tapPending, discards the single tap.
    private func scheduleInterTapTimer() {
        let windowMs = disambiguationWindowMs
        pendingTimerTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(windowMs * 1_000_000))
            guard !Task.isCancelled else { return }
            self.tapPendingTimerFired()
        }
    }

    private func cancelPendingTimer() {
        pendingTimerTask?.cancel()
        pendingTimerTask = nil
    }

    // MARK: - Timer callbacks

    /// Called when the hold disambiguation timer fires without the key being released.
    private func holdTimerFired() {
        guard case .keyDown = hotkeyState else { return }
        hotkeyState = .holding
        onStartRecording?()
    }

    /// Called when the inter-tap timer fires without a second tap arriving.
    private func tapPendingTimerFired() {
        guard case .tapPending = hotkeyState else { return }
        hotkeyState = .idle
        // Single tap with no follow-up — silently discarded per S3-C2 spec.
    }

    // MARK: - Timestamp helpers

    /// Monotonic millisecond timestamp. `systemUptime` is documented monotonic since boot.
    private func nowMillis() -> Double {
        return ProcessInfo.processInfo.systemUptime * 1000.0
    }

    private func acceptStartEdge() -> Bool {
        let now = nowMillis()
        guard now - lastStartEdgeMillis >= minEdgeIntervalMillis else { return false }
        lastStartEdgeMillis = now
        return true
    }

    private func acceptStopEdge() -> Bool {
        let now = nowMillis()
        guard now - lastStopEdgeMillis >= minEdgeIntervalMillis else { return false }
        lastStopEdgeMillis = now
        return true
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
