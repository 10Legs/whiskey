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
        // Sit directly above the waveform HUD idle footprint (22 pt) + margin.
        let origin = CGPoint(
            x: visibleFrame.maxX - width - margin,
            y: visibleFrame.minY + margin + 22 + 6
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

// MARK: - NSPanel Subclass

/// Borderless, non-activating panel that floats above all windows including
/// full-screen apps. Hosts WaveformHUDView via NSHostingView.
///
/// Entitlement note: no special entitlement is required for .floating window
/// level or .canJoinAllSpaces on macOS. The panel stays in the sandbox.
public final class FloatingHUDWindow: NSPanel {

    // MARK: - Properties

    private let hudViewModel: FloatingHUDViewModel
    private var hostingView: NSHostingView<WaveformHUDView>?
    private var moveObserver: NSObjectProtocol?

    // UserDefaults keys for persisting HUD origin.
    private static let originXKey = "com.whiskey.hudOrigin.x"
    private static let originYKey = "com.whiskey.hudOrigin.y"

    // Idle panel footprint used for default positioning.
    private static let idlePanelWidth: CGFloat  = 120
    private static let idlePanelHeight: CGFloat  = 22
    // Recording size — SwiftUI expands in-place; the panel frame uses the larger value
    // only for content sizing. The origin stays fixed.
    private static let recordingPanelWidth: CGFloat  = 200
    private static let recordingPanelHeight: CGFloat = 56

    // Bottom-right margin from screen edge, in points.
    private static let screenMargin: CGFloat = 20

    // MARK: - Init

    public init(viewModel: FloatingHUDViewModel) {
        self.hudViewModel = viewModel

        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        configurePanelBehavior()
        installContentView()
        restoreOrPositionBottomRight()
        installMoveObserver()
    }

    // MARK: - Configuration

    private func configurePanelBehavior() {
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false            // shadow rendered by SwiftUI .shadow() modifier
        hidesOnDeactivate = false
        // Join all Mission Control spaces; display over full-screen apps.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Allow the user to drag the panel by its background.
        isMovableByWindowBackground = true
        animationBehavior = .none
    }

    private func installContentView() {
        let view = WaveformHUDView(viewModel: hudViewModel)
        let hosting = NSHostingView(rootView: view)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        contentView = hosting
        self.hostingView = hosting
    }

    // MARK: - Position Persistence

    /// Restore the saved HUD origin from UserDefaults, or fall back to the
    /// default bottom-right corner. Validates the restored origin against all
    /// connected screens to handle display configuration changes.
    private func restoreOrPositionBottomRight() {
        let defaults = UserDefaults.standard
        let savedX = defaults.object(forKey: Self.originXKey) as? Double
        let savedY = defaults.object(forKey: Self.originYKey) as? Double

        if let originX = savedX, let originY = savedY {
            let origin = CGPoint(x: originX, y: originY)
            // Use the recording size as the bounding box for the on-screen check.
            let panelRect = CGRect(
                origin: origin,
                size: CGSize(width: Self.recordingPanelWidth, height: Self.recordingPanelHeight)
            )
            let isOnScreen = NSScreen.screens.contains { screen in
                screen.frame.intersects(panelRect)
            }
            if isOnScreen {
                setFrameOrigin(origin)
                setContentSize(CGSize(width: Self.recordingPanelWidth, height: Self.recordingPanelHeight))
                return
            }
        }
        positionBottomRight()
    }

    /// Place the panel in the bottom-right corner using the idle footprint.
    /// The SwiftUI frame grows to recording size in-place without repositioning.
    private func positionBottomRight() {
        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        let margin = Self.screenMargin

        let origin = CGPoint(
            x: visibleFrame.maxX - Self.recordingPanelWidth - margin,
            y: visibleFrame.minY + margin
        )
        setFrameOrigin(origin)
        setContentSize(CGSize(width: Self.recordingPanelWidth, height: Self.recordingPanelHeight))
    }

    /// Observe `NSWindow.didMoveNotification` and persist the panel origin.
    private func installMoveObserver() {
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: self,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let origin = self.frame.origin
            let defaults = UserDefaults.standard
            defaults.set(origin.x, forKey: Self.originXKey)
            defaults.set(origin.y, forKey: Self.originYKey)
        }
    }

    deinit {
        if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
    }

    // MARK: - Show / Hide

    public func showHUD() {
        restoreOrPositionBottomRight()
        orderFront(nil)
    }

    public func hideHUD() {
        orderOut(nil)
    }

    // MARK: - NSPanel override

    // Allow the panel to become key only if explicitly needed; prevents
    // stealing focus from the user's active application.
    override public var canBecomeKey: Bool { false }
    override public var canBecomeMain: Bool { false }
}

// MARK: - Controller

/// Thin controller that owns the FloatingHUDWindow and view model.
/// Instantiate once in AppDelegate and wire into hotkey callbacks.
///
/// Example wiring in AppDelegate — add these lines inside startHotkey():
///
///     // 1. Declare at class scope in AppDelegate:
///     //    private var hudController: FloatingHUDWindowController?
///
///     // 2. After `pipeline.onError` and `pipeline.onTranscriptionReady` are wired:
///     let hud = FloatingHUDWindowController(pipeline: pipeline)
///     hudController = hud
///
///     // 3. Wrap the existing hotkey closures:
///     hotkey.onStartRecording = { [weak self, weak hud] in
///         flog.log(.info, "Hotkey down — recording started.")
///         self?.pipeline.startRecording()
///         hud?.recordingDidStart()
///     }
///     hotkey.onStopRecording = { [weak self, weak hud] in
///         guard let self else { return }
///         flog.log(.info, "Hotkey up — running transcription.")
///         self.transcriptionTask?.cancel()
///         self.transcriptionTask = Task {
///             await self.pipeline.stopAndTranscribe()
///         }
///         hud?.recordingDidStop()
///     }
///
/// NOTE: Keep hudController alive as a strong property on AppDelegate.
@MainActor
public final class FloatingHUDWindowController {

    private let viewModel = FloatingHUDViewModel()
    private let window: FloatingHUDWindow

    /// Pass the TranscriptionPipeline. The controller subscribes to its
    /// audioLevelPublisher (which delegates to AudioCaptureService internally).
    public init(pipeline: TranscriptionPipeline) {
        window = FloatingHUDWindow(viewModel: viewModel)
        viewModel.subscribe(toPublisher: pipeline.audioLevelPublisher)
        // Show immediately in idle state so users see the HUD from launch.
        window.showHUD()
    }

    public func recordingDidStart() {
        viewModel.notifyRecordingStarted()
    }

    public func recordingDidStop() {
        viewModel.notifyRecordingStopped()
    }
}

// MARK: - VoiceCommand displayLabel

extension VoiceCommand {
    var displayLabel: String {
        switch self {
        case .insertNewParagraph:  return "New Paragraph"
        case .insertNewLine:       return "New Line"
        case .deleteLastUtterance: return "Scratch That"
        case .uppercaseLastWord:   return "All Caps"
        case .insertPeriod:        return "Period"
        case .insertComma:         return "Comma"
        case .insertQuestionMark:  return "Question Mark"
        }
    }
}
