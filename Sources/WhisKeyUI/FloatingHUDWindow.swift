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
    private var hostingView: NSHostingView<WaveformHUDView>?

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
        positionBottomRight()
    }

    // MARK: - Configuration

    private func configurePanelBehavior() {
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hidesOnDeactivate = false
        // Join all Mission Control spaces; display over full-screen apps.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Allow the panel to receive mouse events for future drag support.
        isMovableByWindowBackground = true
        // Do not appear in Exposé / Mission Control window listing.
        animationBehavior = .none
    }

    private func installContentView() {
        let view = WaveformHUDView(viewModel: hudViewModel)
        let hosting = NSHostingView(rootView: view)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        contentView = hosting
        self.hostingView = hosting
    }

    /// Position the panel 20 pts from the bottom-right corner of the main screen.
    private func positionBottomRight() {
        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        // Use recording size as maximum footprint so the panel never clips.
        let panelWidth: CGFloat = 96
        let panelHeight: CGFloat = 52
        let margin = Self.screenMargin

        let origin = CGPoint(
            x: visibleFrame.maxX - panelWidth - margin,
            y: visibleFrame.minY + margin
        )
        setFrameOrigin(origin)
        setContentSize(CGSize(width: panelWidth, height: panelHeight))
    }

    // MARK: - Show / Hide

    public func showHUD() {
        positionBottomRight()
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
