import AppKit

/// Injects text by writing to NSPasteboard and simulating Cmd+V.
/// Saves and restores the prior clipboard content after a short delay.
final class PasteboardInjector: @unchecked Sendable {

    /// Attempt to inject `text` via pasteboard + Cmd+V simulation.
    /// Always returns true (this strategy has no pre-condition failure mode).
    @MainActor
    func inject(_ text: String) -> Bool {
        let pb = NSPasteboard.general

        // Save prior clipboard string content.
        let priorString = pb.string(forType: .string)

        pb.clearContents()
        pb.setString(text, forType: .string)

        simulateCmdV()

        // Restore prior clipboard after Cmd+V has had time to be processed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            pb.clearContents()
            if let prior = priorString {
                pb.setString(prior, forType: .string)
            }
        }

        return true
    }

    // MARK: - Private

    private func simulateCmdV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let vKeyCode: CGKeyCode = 0x09  // kVK_ANSI_V

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        let keyUp   = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags   = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
