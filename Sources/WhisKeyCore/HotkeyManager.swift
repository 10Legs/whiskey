import Carbon
import AppKit

/// Monitors global hotkey events via CGEventTap.
/// Requires Input Monitoring permission.
public final class HotkeyManager {
    public enum Mode {
        case pushToTalk   // hold = record, release = stop
        case toggle       // tap to start, tap to stop
    }

    public var mode: Mode = .pushToTalk
    public var onStartRecording: (() -> Void)?
    public var onStopRecording: (() -> Void)?

    private var eventTap: CFMachPort?

    public init() {}

    public func start() {
        // TODO: register CGEventTap for configured hotkey
        // Fallback: NSEvent.addGlobalMonitorForEvents for modifier keys
    }

    public func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
    }
}
