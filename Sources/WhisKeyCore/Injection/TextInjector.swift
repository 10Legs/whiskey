import AppKit

/// Injects text into the currently focused UI element using a strategy chain.
///
/// Injection order:
///   1. AXUIElement direct write — no clipboard clobber, requires Accessibility.
///   2. NSPasteboard + simulated Cmd+V — broad compatibility, restores prior clipboard.
///   3. CGEvent keyboard simulation — character-by-character fallback.
public protocol TextInjecting: Sendable {
    func inject(_ text: String) async
}

/// Orchestrator that tries each injection strategy in order.
public final class TextInjector: TextInjecting, @unchecked Sendable {

    private let axInjector: AXInjector
    private let pasteboardInjector: PasteboardInjector
    private let cgEventInjector: CGEventInjector

    public init() {
        axInjector = AXInjector()
        pasteboardInjector = PasteboardInjector()
        cgEventInjector = CGEventInjector()
    }

    public func inject(_ text: String) async {
        if await axInjector.inject(text) { return }
        if await pasteboardInjector.inject(text) { return }
        await cgEventInjector.inject(text)
    }
}
