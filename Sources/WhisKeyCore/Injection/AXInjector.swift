import AppKit
import ApplicationServices

/// Injects text via the Accessibility API (AXUIElement).
/// This is the preferred strategy: it writes directly into the focused field
/// without touching the clipboard.
///
/// Requires Accessibility permission (AXIsProcessTrusted()).
final class AXInjector: @unchecked Sendable {

    /// Attempt to inject `text` into the focused UI element.
    /// - Returns: `true` if injection succeeded, `false` otherwise.
    @MainActor
    func inject(_ text: String) -> Bool {
        guard AXIsProcessTrusted() else { return false }

        // Get the system-wide accessibility element.
        let systemWide = AXUIElementCreateSystemWide()

        // Retrieve the focused UI element.
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard result == .success, let element = focusedElement else { return false }
        let axElement = element as! AXUIElement  // swiftlint:disable:this force_cast

        // Attempt to read the current value so we can append.
        var currentValueRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axElement, kAXValueAttribute as CFString, &currentValueRef)
        let currentText = (currentValueRef as? String) ?? ""

        // Append the new text to whatever is already in the field.
        let newValue = currentText + text as CFTypeRef
        let setResult = AXUIElementSetAttributeValue(
            axElement,
            kAXValueAttribute as CFString,
            newValue
        )

        return setResult == .success
    }
}
