import AppKit
import Darwin
import os.log
import SwiftUI
import WhisKeyCore
import WhisKeyUI

// ggml-metal-device.m looks for default.metallib ONLY in:
//   1. [NSBundle bundleForClass:[GGMLMetalClass class]] (= NSBundle.main for static libs)
//   2. The directory containing the binary (argv[0] parent)
// GGML_METAL_PATH_RESOURCES is used ONLY for the ggml-metal.metal source fallback, not precompiled lib.
//
// SPM places .copy resources into WhisKey_WhisKeyApp.bundle/Contents/Resources/ — neither
// location ggml checks. Fix: copy the metallib into the binary dir at launch so ggml finds it.
do {
    let binaryDir = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
        .deletingLastPathComponent()
    let destURL = binaryDir.appendingPathComponent("default.metallib")

    if !FileManager.default.fileExists(atPath: destURL.path) {
        if let src = Bundle.module.url(forResource: "default", withExtension: "metallib") {
            do {
                try FileManager.default.copyItem(at: src, to: destURL)
                fputs("WhisKey[startup]: copied default.metallib → \(destURL.path)\n", stderr)
            } catch {
                fputs("WhisKey[startup]: ERROR copying default.metallib: \(error)\n", stderr)
            }
        } else {
            fputs("WhisKey[startup]: ERROR — default.metallib not found in Bundle.module\n", stderr)
        }
    } else {
        fputs("WhisKey[startup]: default.metallib already present at \(destURL.path)\n", stderr)
    }
}

private let logger = Logger(subsystem: "com.whiskey.app", category: "AppDelegate")

// MARK: - App Delegate

// swiftlint:disable type_body_length
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let hotkey = HotkeyManager()
    private let permissions = PermissionsManager()
    private let settingsManager = SettingsManager()
    private lazy var modelManager = ModelManager(settings: settingsManager)
    private lazy var pipeline = TranscriptionPipeline(settings: settingsManager)
    private lazy var appContextService = AppContextService(settingsManager: settingsManager)
    private var transcriptionTask: Task<Void, Never>?
    private var settingsWindow: NSWindow?

    // MARK: - Whisper Glass state

    private let pipelineState = PipelineStateModel()
    /// Held alive for audio level forwarding.
    private var hudController: FloatingHUDWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // hide from Dock

        setupStatusItem()
        setupPopover()
        checkPermissionsAndStart()
        checkModelPresence()
    }

    // MARK: - Status Item (Task 3)

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            applyStatusIcon(.idle)
            button.action = #selector(statusItemClicked)
            button.target = self
        }
    }

    private enum IconState { case idle, recording, processing, error }

    private func applyStatusIcon(_ state: IconState) {
        guard let button = statusItem?.button else { return }
        button.image = nil

        switch state {
        case .idle:
            button.image = NSImage(
                systemSymbolName: "waveform.and.mic",
                accessibilityDescription: "WhisKey"
            )
        case .recording:
            // pulse applied via symbolEffect in SwiftUI; NSStatusItem uses NSImage directly.
            // Use a distinct filled icon so the recording state is visually obvious.
            button.image = NSImage(
                systemSymbolName: "mic.fill",
                accessibilityDescription: "Recording"
            )
        case .processing:
            button.image = NSImage(
                systemSymbolName: "waveform",
                accessibilityDescription: "Transcribing"
            )
        case .error:
            button.image = NSImage(
                systemSymbolName: "exclamationmark.triangle",
                accessibilityDescription: "WhisKey Error"
            )
        }
    }

    private func transitionToRecording() {
        applyStatusIcon(.recording)
        pipelineState.recordingState = .recording
    }

    private func transitionToProcessing() {
        applyStatusIcon(.processing)
        pipelineState.recordingState = .processing
    }

    private func transitionToIdle() {
        applyStatusIcon(.idle)
        pipelineState.recordingState = .idle
    }

    private func transitionToError(_ message: String) {
        applyStatusIcon(.error)
        pipelineState.recordingState = .error(message)
        Task {
            try? await Task.sleep(for: .seconds(3))
            transitionToIdle()
        }
    }

    // MARK: - Popover

    private func setupPopover() {
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 300)
        popover.behavior = .transient
        let view = MenuBarView(
            modelManager: modelManager,
            pipelineState: pipelineState,
            onOpenSettings: { [weak self] in
                self?.popover?.performClose(nil)
                self?.openSettings()
            },
            onClear: {}
        )
        popover.contentViewController = NSHostingController(rootView: view)
        self.popover = popover
    }

    @objc private func statusItemClicked() {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Ensure the popover's window becomes key so keyboard shortcuts work.
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Settings Window

    private func openSettings() {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(settings: settingsManager, modelManager: modelManager)
        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "WhisKey Settings"
        window.styleMask = [.titled, .closable]
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.settingsWindow = window
    }

    // MARK: - Model presence check

    /// Checks whether at least one ASR model is on disk.
    ///
    /// If none are found, presents a non-modal `NSAlert` so the user can navigate
    /// to Settings → Models to download one.  Hotkey registration is NOT blocked —
    /// WhisKey remains usable once a model is downloaded without restarting.
    private func checkModelPresence() {
        let flog = FileLogger.shared
        let hasASR = ModelManager.availableModels
            .filter { $0.kind == .asr }
            .contains { modelManager.downloadedModels.contains($0.id) }

        guard !hasASR else { return }

        flog.log(.warn, "No ASR model found. Prompting user to open Settings → Models.")
        logger.warning("No ASR model found in Models directory.")

        // Non-modal: we use beginSheetModal only when a window is available,
        // otherwise fall back to runModal so the alert is always shown.
        let alert = NSAlert()
        alert.messageText = "No Whisper Model Found"
        alert.informativeText = "WhisKey needs a Whisper model to transcribe speech.\n\nOpen Settings → Models and download at least one ASR model to get started."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Later")

        // Use a short async hop to let the menu bar fully settle before showing the alert.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                self.openSettings()
            }
        }
    }

    // MARK: - Permissions + Pipeline

    private func checkPermissionsAndStart() {
        let flog = FileLogger.shared
        let statuses = permissions.statuses()
        var missing: [String] = []

        for (type, status) in statuses {
            flog.log(.info, "Permission \(type.rawValue): \(status)")
        }

        for (type, status) in statuses where status != .granted {
            switch status {
            case .notDetermined:
                if type == .microphone {
                    flog.log(.warn, "Microphone not determined — requesting...")
                    permissions.requestMicrophone { [weak self] granted in
                        Task { @MainActor in
                            if !granted {
                                flog.log(.error, "Microphone permission denied.")
                                logger.warning("Microphone permission denied by user.")
                            } else {
                                flog.log(.info, "Microphone granted.")
                                self?.startHotkey()
                            }
                        }
                    }
                    return
                }
            default:
                missing.append(type.rawValue)
            }
        }

        if !missing.isEmpty {
            flog.log(.warn, "Missing permissions: \(missing.joined(separator: ", "))")
            logger.warning(
                "Missing permissions: \(missing.joined(separator: ", ")). App may not work correctly."
            )
        }

        startHotkey()
    }

    private func startHotkey() {
        let flog = FileLogger.shared
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        flog.log(.info, "WhisKey started (build: \(build)). Log: \(flog.logFilePath)")

        // Apply persisted settings to pipeline.
        pipeline.languageHint = settingsManager.languageHint
        pipeline.cleanupProfile = settingsManager.cleanupProfile

        // Feature 1.3: Start active-app profile service and inject into pipeline.
        appContextService.start()
        pipeline.appContextService = appContextService

        // Wire floating HUD (legacy waveform overlay — kept for recording visual feedback).
        let hud = FloatingHUDWindowController(pipeline: pipeline)
        hudController = hud
        pipelineState.subscribe(toAudioLevel: pipeline.audioLevelPublisher)

        // Wire pipeline callbacks.
        pipeline.onTranscriptionReady = { [weak self] result in
            logger.info("Transcription ready: \"\(result.text)\"")
            flog.log(
                .info,
                "Transcription: \"\(result.text)\" [\(result.language), \(result.durationMs)ms]"
            )
            Task { @MainActor in
                self?.transitionToIdle()
            }
        }
        pipeline.onError = { [weak self] error in
            self?.handlePipelineError(error)
        }

        // Wire hotkey to pipeline + state model.
        hotkey.onStartRecording = { [weak self, weak hud] in
            flog.log(.info, "Hotkey down — recording started.")
            Task { await self?.pipeline.startRecording() }
            self?.transitionToRecording()
            hud?.recordingDidStart()
        }
        hotkey.onStopRecording = { [weak self, weak hud] in
            guard let self else { return }
            flog.log(.info, "Hotkey up — running transcription.")
            self.transitionToProcessing()
            hud?.recordingDidStop()
            self.transcriptionTask?.cancel()
            self.transcriptionTask = Task {
                await self.pipeline.stopAndTranscribe()
            }
        }
        hotkey.mode = .pushToTalk

        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            await self.pipeline.warmUpLLM()
            logger.info("LLM warmup complete.")
        }

        let started = hotkey.start()
        if started {
            flog.log(.info, "HotkeyManager started. Hold Right Option to record.")
            logger.info("HotkeyManager started. Hold Right Option to record.")
        } else {
            let reason = "Input Monitoring permission required. Open System Settings → " +
                "Privacy & Security → Input Monitoring and enable WhisKey."
            flog.log(.error, "HotkeyManager failed to start — \(reason)")
            logger.error("Failed to start HotkeyManager — \(reason)")
            pipeline.onError?(PipelineError.hotkeyUnavailable(reason))
        }
    }

    // MARK: - Pipeline Error Handling

    private func handlePipelineError(_ error: Error) {
        let flog = FileLogger.shared
        logger.error("Pipeline error: \(error.localizedDescription)")
        flog.log(.error, "Pipeline error: \(error.localizedDescription)")

        guard let pipelineError = error as? PipelineError else {
            flog.log(.error, "Pipeline error of unknown type: \(String(describing: error))")
            AppNotifications.post(.transcriptionFailed(error))
            surfaceErrorInPopover(error.localizedDescription, action: nil)
            return
        }

        guard pipelineError.severity != .info else {
            flog.log(.info, "Pipeline state event (suppressed from UI): \(pipelineError.localizedDescription)")
            return
        }

        switch pipelineError {
        case .alreadyRecording, .notRecording:
            break
        case .captureError(let underlying):
            AppNotifications.post(.captureUnavailable(underlying.localizedDescription))
            surfaceErrorInPopover(underlying.localizedDescription, action: .retry)
        case .microphonePermissionDenied:
            AppNotifications.post(.permissionDenied("Microphone access is required for audio capture."))
            surfaceErrorInPopover(
                "Microphone access denied. Grant permission in System Settings.",
                action: .openSettings
            )
        case .transcriptionError(let underlying):
            AppNotifications.post(.transcriptionFailed(underlying))
            surfaceErrorInPopover(underlying.localizedDescription, action: .retry)
        case .injectionSkipped(let reason):
            AppNotifications.post(.injectionFailed(reason))
            surfaceErrorInPopover("Text injection skipped: \(reason)", action: nil)
        case .hotkeyUnavailable(let reason):
            AppNotifications.post(.hotkeyUnavailable(reason))
            surfaceErrorInPopover("Hotkey unavailable: \(reason)", action: .openSettings)
        case .llmCleanupFailed:
            break
        }

        transitionToError(pipelineError.localizedDescription)
    }

    private func surfaceErrorInPopover(_ text: String, action: PipelineErrorMessage.ErrorAction?) {
        let msg = PipelineErrorMessage(text: text, action: action)
        pipelineState.postError(msg)
    }
}
// swiftlint:enable type_body_length

// MARK: - Entry Point

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
