@preconcurrency import AppKit

/// Injects text into the currently focused UI element using a strategy chain.
///
/// Injection order (when method == .auto):
///   1. AXUIElement direct write — no clipboard clobber, requires Accessibility.
///   2. NSPasteboard + simulated Cmd+V — broad compatibility, restores prior clipboard.
///   3. CGEvent keyboard simulation — character-by-character fallback.
///
/// When an explicit method is supplied, that strategy is attempted first and falls
/// through to lower strategies on failure — it never hard-fails and never silently
/// drops the user's dictation. See ADR-009: Per-App Injection-Method Override.
public protocol TextInjecting: Sendable {
    /// Inject `text` using the specified strategy.
    /// - Parameters:
    ///   - text: The string to inject.
    ///   - capturedElement: AX element captured at hotkey-down time, if available.
    ///   - method: Which injection strategy to attempt first.
    func inject(_ text: String, capturedElement: AXUIElement?, method: InjectionMethod) async
}

public extension TextInjecting {
    /// Convenience overload that defaults to `.auto` (unchanged waterfall).
    /// Secondary call sites — voice-command newlines, history re-injection — use
    /// this so they are unaffected by ADR-009 and always run the full waterfall.
    func inject(_ text: String, capturedElement: AXUIElement? = nil) async {
        await inject(text, capturedElement: capturedElement, method: .auto)
    }
}

/// Orchestrator that tries each injection strategy in order.
public final class TextInjector: TextInjecting, @unchecked Sendable {

    private let axInjector: AXInjector
    private let pasteboardInjector: PasteboardInjector
    private let cgEventInjector: CGEventInjector
    private let flog = FileLogger.shared

    public init() {
        axInjector = AXInjector()
        pasteboardInjector = PasteboardInjector()
        cgEventInjector = CGEventInjector()
    }

    public func inject(_ text: String,
                       capturedElement: AXUIElement? = nil,
                       method: InjectionMethod = .auto) async {
        flog.log(.info, "TextInjector: method=\(method.rawValue)")
        switch method {
        case .auto:
            // UNCHANGED legacy waterfall — identical code path to pre-ADR-009.
            // This is a regression-tested invariant (ADR-009 §6, test #3).
            if await axInjector.inject(text, capturedElement: capturedElement) { return }
            if await pasteboardInjector.inject(text) { return }
            await cgEventInjector.inject(text)

        case .ax:
            // Prefer AX; fall through to Pasteboard → CGEvent on failure.
            // Behaviourally close to .auto (AX is still attempted first).
            if await axInjector.inject(text, capturedElement: capturedElement) { return }
            flog.log(.info, "TextInjector: .ax failed — falling through to pasteboard/cgEvent")
            await pasteboardAndCGEventFallback(text)

        case .pasteboard:
            // Skip AX entirely (e.g. Telegram, Messages — AX lies).
            // On pasteboard failure, fall through to CGEvent.
            if await pasteboardInjector.inject(text) { return }
            flog.log(.info, "TextInjector: .pasteboard failed — falling through to cgEvent")
            await cgEventInjector.inject(text)

        case .cgEvent:
            // Terminal stage; nothing below it.
            await cgEventInjector.inject(text)
        }
    }

    // MARK: - Private

    /// Runs Pasteboard → CGEvent. Called as the fallback chain for `.ax` failures.
    private func pasteboardAndCGEventFallback(_ text: String) async {
        if await pasteboardInjector.inject(text) { return }
        await cgEventInjector.inject(text)
    }
}
