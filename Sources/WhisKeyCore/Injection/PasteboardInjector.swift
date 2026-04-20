import AppKit
import os.log

private let logger = Logger(subsystem: "com.whiskey.app", category: "PasteboardInjector")

/// Injects text by writing to NSPasteboard and simulating Cmd+V.
/// Saves and restores the prior clipboard content after a short delay.
final class PasteboardInjector: @unchecked Sendable {

    @MainActor
    func inject(_ text: String) -> Bool {
        guard AXIsProcessTrusted() else { return false }

        let pb = NSPasteboard.general
        let priorString = pb.string(forType: .string)

        pb.clearContents()
        pb.setString(text, forType: .string)
        // Signal clipboard managers (Raycast, Paste, CopyClip, etc.) to skip persisting this transient write
        pb.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))

        simulateCmdV()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            pb.clearContents()
            if let prior = priorString {
                pb.setString(prior, forType: .string)
            }
        }

        return true
    }

    private func simulateCmdV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let vKeyCode: CGKeyCode = 0x09  // kVK_ANSI_V

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        let keyUp   = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags   = .maskCommand
        keyDown?.post(tap: .cgSessionEventTap)
        keyUp?.post(tap: .cgSessionEventTap)
    }
}
