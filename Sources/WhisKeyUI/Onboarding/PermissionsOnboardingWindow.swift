import AppKit
import SwiftUI
import WhisKeyCore

/// NSWindowController that hosts the permissions onboarding flow.
///
/// The window is 540×480 pt, fixed size, with no close/minimize/zoom buttons.
/// It uses a hidden title bar and `.regularMaterial` background via a transparent
/// NSWindow backing a SwiftUI root view.
///
/// Entitlement rationale: no entitlements added by this file; it relies on
/// permissions already declared in the target (Microphone, Accessibility, Input Monitoring).
@MainActor
public final class PermissionsOnboardingWindow: NSWindowController {

    private let permissions: PermissionsManager
    private var onComplete: (() -> Void)?

    public init(permissions: PermissionsManager, onComplete: @escaping () -> Void) {
        self.permissions = permissions
        self.onComplete = onComplete

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 480),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // Hide window chrome — no close, minimize, zoom
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true

        // Material background via transparent NSWindow
        window.isOpaque = false
        window.backgroundColor = .clear

        // Fixed size
        window.minSize = NSSize(width: 540, height: 480)
        window.maxSize = NSSize(width: 540, height: 480)

        // Normal level — not floating
        window.level = .normal

        // Corner radius via layer
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.cornerRadius = 12
        window.contentView?.layer?.masksToBounds = true

        super.init(window: window)

        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not implemented") }

    public func show() {
        guard let window else { return }

        let rootView = PermissionsOnboardingView(permissions: permissions) { [weak self] in
            self?.close()
            self?.onComplete?()
            self?.onComplete = nil
        }

        window.contentViewController = NSHostingController(rootView: rootView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
