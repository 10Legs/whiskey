import AppKit
import os.log
import SwiftUI
import WhisKeyCore
import WhisKeyUI

private let logger = Logger(subsystem: "com.whiskey.app", category: "AppDelegate")

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let pipeline = TranscriptionPipeline()
    private let hotkey = HotkeyManager()
    private let permissions = PermissionsManager()
    private let settingsManager = SettingsManager()
    private var transcriptionTask: Task<Void, Never>?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // hide from Dock

        setupStatusItem()
        setupPopover()
        checkPermissionsAndStart()
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

        let settingsView = SettingsView(settings: settingsManager)
        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "WhisKey Settings"
        window.styleMask = [.titled, .closable]
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.settingsWindow = window
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
        flog.log(.info, "WhisKey started. Log: \(flog.logFilePath)")

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
        pipeline.onError = { error in
            logger.error("Pipeline error: \(error.localizedDescription)")
            flog.log(.error, error.localizedDescription)
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

        let started = hotkey.start()
        if started {
            flog.log(.info, "HotkeyManager started. Hold Right Option to record.")
            logger.info("HotkeyManager started. Hold Right Option to record.")
        } else {
            flog.log(
                .error,
                "HotkeyManager failed to start — Input Monitoring permission required."
            )
            logger.error("Failed to start HotkeyManager — Input Monitoring permission required.")
        }
    }
}

// MARK: - Entry Point

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
