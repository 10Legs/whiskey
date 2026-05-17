import AppKit

/// Last-resort text injection via CGEvent keyboard simulation.
/// Synthesizes individual key events for each Unicode character in `text`.
///
/// Note: This approach works for printable ASCII. For non-ASCII characters,
/// it uses CGEventKeyboardSetUnicodeString to post the raw Unicode codepoints.
///
/// CGEvent posting is dispatched on a dedicated serial background queue (R9) so
/// that long strings never block the main thread.
final class CGEventInjector: @unchecked Sendable {

    /// Serial queue at userInteractive QoS — high enough for responsive injection
    /// but guaranteed off the main thread.
    private let eventQueue = DispatchQueue(
        label: "com.whiskey.cgevent-injector",
        qos: .userInteractive
    )

    func inject(_ text: String) async {
        guard AXIsProcessTrusted() else { return }

        // Hop to the dedicated background queue for all CGEvent posting so the
        // main thread is never blocked regardless of string length (R9).
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            eventQueue.async {
                let source = CGEventSource(stateID: .hidSystemState)

                for scalar in text.unicodeScalars {
                    let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
                    let keyUp   = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)

                    guard keyDown != nil, keyUp != nil else { continue }

                    // Set the Unicode character directly on the event.
                    var unichar = UniChar(scalar.value & 0xFFFF)
                    keyDown?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unichar)
                    keyUp?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unichar)

                    keyDown?.post(tap: .cgSessionEventTap)
                    keyUp?.post(tap: .cgSessionEventTap)

                    // Small delay to avoid flooding the event queue (5 ms).
                    Thread.sleep(forTimeInterval: 0.005)
                }

                continuation.resume()
            }
        }
    }
}
