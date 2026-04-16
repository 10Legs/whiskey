import AppKit

/// Last-resort text injection via CGEvent keyboard simulation.
/// Synthesizes individual key events for each Unicode character in `text`.
///
/// Note: This approach works for printable ASCII. For non-ASCII characters,
/// it uses CGEventKeyboardSetUnicodeString to post the raw Unicode codepoints.
final class CGEventInjector: @unchecked Sendable {

    func inject(_ text: String) async {
        guard AXIsProcessTrusted() else { return }
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

            // Small delay to avoid flooding the event queue.
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}
