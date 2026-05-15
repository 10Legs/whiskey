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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let hotkey = HotkeyManager()
    private let permissions = PermissionsManager()
    private let settingsManager = SettingsManager()
    private lazy var modelManager = ModelManager(settings: settingsManager)
    private lazy var pipeline = TranscriptionPipeline(settings: settingsManager)
    private var transcriptionTask: Task<Void, Never>?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // hide from Dock

        setupStatusItem()
        setupPopover()
        checkPermissionsAndStart()
        checkModelPresence()
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(
                systemSymbolName: "waveform.and.mic",
                accessibilityDescription: "WhisKey"
            )
            button.action = #selector(statusItemClicked)
            button.target = self
        }
    }

    // MARK: - Popover

    private func setupPopover() {
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 260)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(
                onOpenSettings: { [weak self] in
                    self?.popover?.performClose(nil)
                    self?.openSettings()
                }
            )
        )
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

    private func checkModelPresence() {
        if modelManager.downloadedModels.isEmpty {
            let flog = FileLogger.shared
            flog.log(.warn, "No Whisper models found in Models directory. Open Settings → General to download a model.")
            logger.warning("No Whisper models found. Open Settings → General to download a model.")
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

        // Wire pipeline callbacks.
        pipeline.onTranscriptionReady = { result in
            logger.info("Transcription ready: \"\(result.text)\"")
            flog.log(
                .info,
                "Transcription: \"\(result.text)\" [\(result.language), \(result.durationMs)ms]"
            )
        }
        pipeline.onError = { [weak self] error in
            self?.handlePipelineError(error)
        }

        // Wire hotkey to pipeline.
        hotkey.onStartRecording = { [weak self] in
            flog.log(.info, "Hotkey down — recording started.")
            self?.pipeline.startRecording()
        }
        hotkey.onStopRecording = { [weak self] in
            guard let self else { return }
            flog.log(.info, "Hotkey up — running transcription.")
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
            // Route through the same structured error path so the UI mapping is
            // consistent with pipeline-originated errors.
            pipeline.onError?(PipelineError.hotkeyUnavailable(reason))
        }
    }

    // MARK: - Pipeline Error Handling

    private func handlePipelineError(_ error: Error) {
        let flog = FileLogger.shared
        logger.error("Pipeline error: \(error.localizedDescription)")
        flog.log(.error, "Pipeline error: \(error.localizedDescription)")

        guard let pipelineError = error as? PipelineError else {
            // Untyped error — escalate as a generic transcription failure.
            flog.log(.error, "Pipeline error of unknown type: \(String(describing: error))")
            AppNotifications.post(.transcriptionFailed(error))
            return
        }

        // Info-severity errors are logged only, never surfaced as notifications.
        guard pipelineError.severity != .info else {
            flog.log(.info, "Pipeline state event (suppressed from UI): \(pipelineError.localizedDescription)")
            return
        }

        switch pipelineError {
        case .alreadyRecording, .notRecording:
            break
        case .captureError(let underlying):
            AppNotifications.post(.captureUnavailable(underlying.localizedDescription))
        case .microphonePermissionDenied:
            AppNotifications.post(.permissionDenied("Microphone access is required for audio capture."))
        case .transcriptionError(let underlying):
            AppNotifications.post(.transcriptionFailed(underlying))
        case .injectionSkipped(let reason):
            AppNotifications.post(.injectionFailed(reason))
        case .hotkeyUnavailable(let reason):
            AppNotifications.post(.hotkeyUnavailable(reason))
        case .llmCleanupFailed:
            break
        }
    }
}

// MARK: - Entry Point

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
