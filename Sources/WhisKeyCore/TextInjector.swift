import AppKit
import ApplicationServices

/// Injects text into the currently focused UI element.
///
/// Injection hierarchy:
///   1. AXUIElement direct write (Accessibility API) — no clipboard clobber
///   2. NSPasteboard + simulated Cmd+V — broad compatibility, restores prior clipboard
///   3. CGEvent keyboard simulation — last resort
///
/// Requires Accessibility permission for strategy 1.
/// Requires Input Monitoring permission for strategy 3.
public final class TextInjector {

    public init() {}

    public func inject(_ text: String) {
        if tryAXInject(text) { return }
        if tryPasteboardInject(text) { return }
        cgEventInject(text)
    }

    // MARK: - Strategy 1: Accessibility API

    private func tryAXInject(_ text: String) -> Bool {
        // TODO: AXUIElementCopyAttributeValue(kAXFocusedUIElementAttribute)
        // then AXUIElementSetAttributeValue(kAXValueAttribute)
        return false
    }

    // MARK: - Strategy 2: Pasteboard + Cmd+V

    private func tryPasteboardInject(_ text: String) -> Bool {
        let pb = NSPasteboard.general
        let prior = pb.string(forType: .string)
        pb.clearContents()
        pb.setString(text, forType: .string)

        // Simulate Cmd+V
        let source = CGEventSource(stateID: .hidSystemState)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)

        // Restore prior clipboard after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if let prior {
                pb.clearContents()
                pb.setString(prior, forType: .string)
            }
        }
        return true
    }

    // MARK: - Strategy 3: CGEvent keyboard simulation

    private func cgEventInject(_ text: String) {
        // TODO: simulate keystrokes for each character via CGEventCreateKeyboardEvent
    }
}
