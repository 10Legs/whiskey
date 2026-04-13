import AppKit

/// Last-resort text injection via CGEvent keyboard simulation.
/// Synthesizes individual key events for each Unicode character in `text`.
///
/// Note: This approach works for printable ASCII. For non-ASCII characters,
/// it uses CGEventKeyboardSetUnicodeString to post the raw Unicode codepoints.
final class CGEventInjector: @unchecked Sendable {

    @MainActor
    func inject(_ text: String) {
        let source = CGEventSource(stateID: .hidSystemState)

        for scalar in text.unicodeScalars {
            var keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            var keyUp   = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)

            guard keyDown != nil, keyUp != nil else { continue }

            // Set the Unicode character directly on the event.
            var unichar = UniChar(scalar.value & 0xFFFF)
            keyDown?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unichar)
            keyUp?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unichar)

            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)

            // Small delay to avoid flooding the event queue.
            Thread.sleep(forTimeInterval: 0.005)
        }
    }
}
