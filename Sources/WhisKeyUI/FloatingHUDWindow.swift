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
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .none

        let hosting = NSHostingView(rootView: VoiceCommandHUDContentView(label: ""))
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
        (panel.contentView as? NSHostingView<VoiceCommandHUDContentView>)?.rootView =
            VoiceCommandHUDContentView(label: label)
        position()
        panel.orderFront(nil)

        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            self?.panel.orderOut(nil)
        }
    }

    private func position() {
        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        let width: CGFloat = 180
        let height: CGFloat = 32
        let margin: CGFloat = 20
        // Sit directly above the waveform HUD (waveform HUD is 52 pt tall + 20 pt margin).
        let origin = CGPoint(
            x: visibleFrame.maxX - width - margin,
            y: visibleFrame.minY + margin + 52 + 6
        )
        panel.setFrameOrigin(origin)
        panel.setContentSize(CGSize(width: width, height: height))
    }
}

private struct VoiceCommandHUDContentView: View {
    let label: String

    private let bgColor   = Color(red: 0.024, green: 0.031, blue: 0.031)
    private let neonGreen = Color(red: 0, green: 1, blue: 0.533)

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundColor(neonGreen)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(bgColor)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(neonGreen.opacity(0.6), lineWidth: 1)
            )
            .cornerRadius(2)
    }
}

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
