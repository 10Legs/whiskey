import AppKit
import Combine
import SwiftUI
import WhisKeyCore

// MARK: - NSPanel Subclass

/// Borderless, non-activating panel that floats above all windows including
/// full-screen apps. Hosts WaveformHUDView via NSHostingView.
///
/// Entitlement note: no special entitlement is required for .floating window
/// level or .canJoinAllSpaces on macOS. The panel stays in the sandbox.
public final class FloatingHUDWindow: NSPanel {

    // MARK: - Properties

    private let hudViewModel: FloatingHUDViewModel
    private let settingsManager: SettingsManager
    private var hostingView: NSHostingView<WaveformHUDView>?
    private var moveObserver: NSObjectProtocol?
    private var idlePillCenter: CGPoint?
    private var recordingCancellable: AnyCancellable?

    // UserDefaults keys for persisting HUD origin.
    private static let originXKey = "com.whiskey.hudOrigin.x"
    private static let originYKey = "com.whiskey.hudOrigin.y"

    // Idle panel footprint — matches WaveformHUDView.idleSize (48×8 pt true pill).
    static let idlePanelWidth: CGFloat  = 48
    static let idlePanelHeight: CGFloat  = 8
    // Recording size — SwiftUI expands in-place; 80 pt height accommodates caption strip.
    static let recordingPanelWidth: CGFloat  = 200
    static let recordingPanelHeight: CGFloat = 80

    // Bottom-right margin from screen edge, in points.
    private static let screenMargin: CGFloat = 20

    // MARK: - Init

    public init(viewModel: FloatingHUDViewModel, settingsManager: SettingsManager) {
        self.hudViewModel = viewModel
        self.settingsManager = settingsManager

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
        subscribeToRecordingState()
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

    // MARK: - Recording State Subscription

    private func subscribeToRecordingState() {
        recordingCancellable = hudViewModel.$isRecording
            .receive(on: RunLoop.main)
            .sink { [weak self] isRecording in
                guard let self else { return }
                if isRecording {
                    self.expandFromCenter()
                } else {
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        try? await Task.sleep(for: .milliseconds(420))
                        self.collapseToCenter()
                    }
                }
            }
    }

    // MARK: - Expand / Collapse

    private func expandFromCenter() {
        let center = CGPoint(
            x: frame.origin.x + Self.idlePanelWidth / 2,
            y: frame.origin.y + Self.idlePanelHeight / 2
        )
        idlePillCenter = center
        let expandedRect = centeredRecordingRect(around: center)
        setFrame(expandedRect, display: true, animate: false)
    }

    private func collapseToCenter() {
        guard let center = idlePillCenter else { return }
        let idleRect = NSRect(
            x: center.x - Self.idlePanelWidth / 2,
            y: center.y - Self.idlePanelHeight / 2,
            width: Self.idlePanelWidth,
            height: Self.idlePanelHeight
        )
        setFrame(idleRect, display: true, animate: false)
        idlePillCenter = nil
    }

    // MARK: - Geometry Helpers

    private func centeredRecordingRect(around center: CGPoint) -> NSRect {
        let expandedX = center.x - Self.recordingPanelWidth / 2
        let expandedY = center.y - Self.recordingPanelHeight / 2
        let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main
        let usable = screen?.visibleFrame ?? NSRect(
            x: expandedX, y: expandedY,
            width: Self.recordingPanelWidth, height: Self.recordingPanelHeight
        )
        let clampedX = max(usable.minX, min(expandedX, usable.maxX - Self.recordingPanelWidth))
        let clampedY = max(usable.minY, min(expandedY, usable.maxY - Self.recordingPanelHeight))
        return NSRect(
            x: clampedX, y: clampedY,
            width: Self.recordingPanelWidth, height: Self.recordingPanelHeight
        )
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
            let panelRect = CGRect(
                origin: origin,
                size: CGSize(width: Self.idlePanelWidth, height: Self.idlePanelHeight)
            )
            let isOnScreen = NSScreen.screens.contains { screen in
                screen.frame.intersects(panelRect)
            }
            if isOnScreen {
                setFrameOrigin(origin)
                setContentSize(CGSize(width: Self.idlePanelWidth, height: Self.idlePanelHeight))
                return
            }
        }
        positionBottomRight()
    }

    /// Place the panel in the bottom-right corner at idle size (48×8 pt).
    /// The window is idle-sized at rest; expandFromCenter() grows it when recording begins.
    private func positionBottomRight() {
        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        let margin = Self.screenMargin
        let originX = visibleFrame.maxX - Self.idlePanelWidth - margin
        let originY = visibleFrame.minY + margin
        setFrameOrigin(CGPoint(x: originX, y: originY))
        setContentSize(CGSize(width: Self.idlePanelWidth, height: Self.idlePanelHeight))
    }

    /// Observe `NSWindow.didMoveNotification` and persist the panel origin.
    /// Only persist while idle — during recording the window is expanded and
    /// the persisted origin should remain the idle pill position.
    private func installMoveObserver() {
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: self,
            queue: .main
        ) { [weak self] _ in
            guard let self, !self.hudViewModel.isRecording else { return }
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
///     let hud = FloatingHUDWindowController(pipeline: pipeline, settingsManager: settingsManager)
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

    /// Pass the TranscriptionPipeline and SettingsManager. The controller subscribes to the
    /// pipeline's audioLevelPublisher. SettingsManager is forwarded to WaveformHUDView for
    /// live waveform-style reads.
    public init(pipeline: TranscriptionPipeline, settingsManager: SettingsManager) {
        window = FloatingHUDWindow(viewModel: viewModel, settingsManager: settingsManager)
        viewModel.subscribe(toPublisher: pipeline.audioLevelPublisher)
    }

    /// Show or hide the HUD panel. Called at launch to honour the persisted setting,
    /// and from the live-sync observer whenever the user toggles the setting.
    public func setVisible(_ visible: Bool) {
        if visible {
            window.showHUD()
        } else {
            window.hideHUD()
        }
    }

    public func recordingDidStart() { viewModel.notifyRecordingStarted() }
    public func recordingDidStop() { viewModel.notifyRecordingStopped() }

    /// Forward partial transcripts to the caption strip.
    public func subscribeToPartials(_ publisher: AnyPublisher<String, Never>) {
        viewModel.subscribeToPartials(publisher)
    }

    /// Immediately clear the caption strip, cancelling any active linger timer.
    /// Called directly to reset state (e.g. before a new recording starts).
    public func clearPreview() { viewModel.clearPreview() }

    /// Apply user-configured linger behaviour after the final transcript is injected.
    public func handlePreviewClear(mode: PreviewLingerMode) {
        viewModel.handlePreviewClear(mode: mode)
    }
}
