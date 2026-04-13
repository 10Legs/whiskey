import AppKit
import WhisKeyCore
import os.log

private let logger = Logger(subsystem: "com.whiskey.app", category: "AppDelegate")

// Entry point — launches as a menu bar app (no Dock icon).
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private let pipeline = TranscriptionPipeline()
    private let hotkey = HotkeyManager()
    private let permissions = PermissionsManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // hide from Dock

        setupStatusItem()
        checkPermissionsAndStart()
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "waveform.and.mic", accessibilityDescription: "WhisKey")
            button.action = #selector(statusItemClicked)
            button.target = self
        }
    }

    @objc private func statusItemClicked() {
        // Placeholder for future settings popover.
        logger.debug("Status item clicked.")
    }

    // MARK: - Permissions + Pipeline

    private func checkPermissionsAndStart() {
        let statuses = permissions.statuses()
        var missing: [String] = []

        for (type, status) in statuses where status != .granted {
            switch status {
            case .notDetermined:
                if type == .microphone {
                    permissions.requestMicrophone { [weak self] granted in
                        if !granted {
                            logger.warning("Microphone permission denied by user.")
                        } else {
                            self?.startHotkey()
                        }
                    }
                    return
                }
            default:
                missing.append(type.rawValue)
            }
        }

        if !missing.isEmpty {
            logger.warning("Missing permissions: \(missing.joined(separator: ", ")). App may not work correctly.")
            // Still start — user can grant via System Settings and relaunch.
        }

        startHotkey()
    }

    private func startHotkey() {
        // Wire pipeline callbacks.
        pipeline.onTranscriptionReady = { result in
            logger.info("Transcription ready: \"\(result.text)\"")
        }
        pipeline.onError = { error in
            logger.error("Pipeline error: \(error.localizedDescription)")
        }

        // Wire hotkey to pipeline.
        hotkey.onStartRecording = { [weak self] in
            self?.pipeline.startRecording()
        }
        hotkey.onStopRecording = { [weak self] in
            Task {
                await self?.pipeline.stopAndTranscribe()
            }
        }
        hotkey.mode = .pushToTalk

        let started = hotkey.start()
        if started {
            logger.info("HotkeyManager started. Hold Right Option to record.")
        } else {
            logger.error("Failed to start HotkeyManager — Input Monitoring permission required.")
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
