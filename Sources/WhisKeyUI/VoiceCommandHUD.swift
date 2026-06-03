import AppKit
import Combine
import SwiftUI
import WhisKeyCore

// MARK: - Voice Command HUD (S5-UX-1)

/// A borderless, non-activating panel that briefly shows the name of the last
/// voice command executed. Auto-dismisses after 1.5 seconds. Positioned in the
/// bottom-right corner above the waveform HUD.
@MainActor
public final class VoiceCommandHUDController {

    private let panel: NSPanel
    private var dismissTask: Task<Void, Never>?
    private var observer: NSObjectProtocol?

    /// Width/height must match the SwiftUI frame declared in VoiceCommandHUDContentView.
    private static let panelWidth: CGFloat = 200
    private static let panelHeight: CGFloat = 36

    public init() {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false          // shadow rendered by SwiftUI .shadow() modifier
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .none

        let contentView = VoiceCommandHUDContentView(label: "")
        let hosting = NSHostingView(rootView: contentView)
        panel.contentView = hosting

        observer = NotificationCenter.default.addObserver(
            forName: TranscriptionPipeline.voiceCommandDidExecute,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let command = notification.userInfo?[TranscriptionPipeline.voiceCommandKey] as? VoiceCommand else { return }
            self?.show(label: command.displayLabel)
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    private func show(label: String) {
        dismissTask?.cancel()

        // Swap rootView to trigger entry animation on a fresh VoiceCommandHUDContentView.
        let hosting = panel.contentView as? NSHostingView<VoiceCommandHUDContentView>
        hosting?.rootView = VoiceCommandHUDContentView(label: label)

        position()
        panel.orderFront(nil)
        NSAccessibility.post(element: NSApp, notification: .announcementRequested, userInfo: [
            NSAccessibility.NotificationUserInfoKey.announcement: label,
            NSAccessibility.NotificationUserInfoKey.priority: NSAccessibilityPriorityLevel.high.rawValue
        ])

        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            // Signal the content view to animate out, then order-out after delay.
            await self?.animateOutAndDismiss()
        }
    }

    @MainActor
    private func animateOutAndDismiss() async {
        // Swap to a dismissing view so the exit animation plays.
        (panel.contentView as? NSHostingView<VoiceCommandHUDContentView>)?.rootView =
            VoiceCommandHUDContentView(label: "", dismissing: true)
        try? await Task.sleep(for: .milliseconds(150))
        panel.orderOut(nil)
    }

    private func position() {
        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        let width = Self.panelWidth
        let height = Self.panelHeight
        let margin: CGFloat = 20
        // Sit directly above the waveform HUD idle footprint (8 pt) + margin.
        let origin = CGPoint(
            x: visibleFrame.maxX - width - margin,
            y: visibleFrame.minY + margin + 8 + 6
        )
        panel.setFrameOrigin(origin)
        panel.setContentSize(CGSize(width: width, height: height))
    }
}

// MARK: - Voice Command HUD Content View

private struct VoiceCommandHUDContentView: View {
    let label: String
    var dismissing: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        HStack(spacing: HalideTokens.spacing8) {
            Circle()
                .fill(HalideTokens.accentAmber)
                .frame(width: 6, height: 6)

            Text(label)
                .font(.callout.weight(.medium))
                .foregroundColor(HalideTokens.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, HalideTokens.spacing12)
        .padding(.vertical, HalideTokens.spacing8)
        .frame(width: 200, height: 36)
        .background {
            RoundedRectangle(cornerRadius: HalideTokens.radiusMedium)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: HalideTokens.radiusMedium)
                .stroke(HalideTokens.borderSubtle, lineWidth: 1)
        }
        .shadow(
            color: HalideTokens.hudShadowColor.opacity(HalideTokens.hudShadowOpacity),
            radius: HalideTokens.hudShadowRadius,
            x: 0,
            y: HalideTokens.hudShadowY
        )
        .opacity(entryOpacity)
        .offset(y: entryOffsetY)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: appeared)
        .onAppear {
            if !dismissing {
                appeared = true
            }
        }
        .onChange(of: dismissing) { _, isDismissing in
            if isDismissing { appeared = false }
        }
    }

    private var entryOpacity: Double {
        guard !reduceMotion else { return 1 }
        if dismissing { return appeared ? 0 : 1 }
        return appeared ? 1 : 0
    }

    private var entryOffsetY: Double {
        guard !reduceMotion else { return 0 }
        if dismissing { return appeared ? 8 : 0 }
        return appeared ? 0 : 8
    }
}
