import AppKit
import ApplicationServices
import os.log

private let logger = Logger(subsystem: "com.whiskey.app", category: "AXInjector")

/// Roles that may support kAXSelectedTextAttribute write (native AppKit only).
private let candidateRoles: Set<String> = [
    kAXTextFieldRole as String,
    kAXTextAreaRole as String,
    kAXComboBoxRole as String
]

/// Apps that report AXTextArea but silently ignore kAXSelectedTextAttribute write.
/// These fall through to PasteboardInjector (Cmd+V).
private let axBlocklist: Set<String> = [
    "com.googlecode.iterm2",
    "com.apple.Terminal",
    "com.microsoft.VSCode",
    "com.google.Chrome",
    "com.google.Chrome.canary",
    "org.mozilla.firefox",
    "com.microsoft.edgemac",
    "com.brave.Browser",
    "com.todesktop.230313mzl4w4u92", // Cursor
    "com.apple.MobileSMS"            // Messages — compose field accepts AX role but silently drops writes
]

/// Injects text via the Accessibility API (AXUIElement).
/// Only injects into native AppKit text fields not in the blocklist.
/// Falls through for terminals, browsers, and Electron apps.
final class AXInjector: @unchecked Sendable {

    private let flog = FileLogger.shared

    @MainActor
    func inject(_ text: String, capturedElement: AXUIElement? = nil) -> Bool {
        guard AXIsProcessTrusted() else { return false }

        let axElement: AXUIElement
        if let captured = capturedElement {
            axElement = captured
        } else {
            let systemWide = AXUIElementCreateSystemWide()
            var focusedRef: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(
                systemWide,
                kAXFocusedUIElementAttribute as CFString,
                &focusedRef
            )
            guard result == .success, let element = focusedRef else { return false }
            axElement = element as! AXUIElement  // swiftlint:disable:this force_cast
        }

        // Check element role — skip unsupported roles immediately.
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axElement, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? "unknown"
        guard candidateRoles.contains(role) else { return false }

        // Skip blocklisted apps that lie about AX write support.
        var pid: pid_t = 0
        AXUIElementGetPid(axElement, &pid)
        if pid > 0, let app = NSRunningApplication(processIdentifier: pid) {
            if axBlocklist.contains(app.bundleIdentifier ?? "") { return false }
        }

        let setResult = AXUIElementSetAttributeValue(
            axElement,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )

        if setResult != .success {
            flog.log(.warn, "AXInjector: set failed (code: \(setResult.rawValue))")
        }

        return setResult == .success
    }
}
