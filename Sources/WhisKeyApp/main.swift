// swiftlint:disable file_length
// main.swift is the single-file entry point for the app process. AppDelegate extraction
// into separate files is deferred to a future refactor sprint.
import AppKit
import Darwin
import os.log
import ServiceManagement
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
    // S3-T6: Multi-hotkey binding store. Created once; shared with SettingsView.
    private let bindingStore = HotkeyBindingStore()
    // S4-T7: Per-app tone profile store. Created once; shared with SettingsView and pipeline.
    private let toneProfileStore = AppToneProfileStore.shared
    private lazy var modelManager = ModelManager(settings: settingsManager)
    private lazy var pipeline = TranscriptionPipeline(settings: settingsManager)
    private lazy var appContextService = AppContextService(settingsManager: settingsManager)
    private var transcriptionTask: Task<Void, Never>?
    // S4-T4: Multi-hotkey dispatcher — owns all 4 action → callback mappings.
    private var hotkeyDispatcher: HotkeyDispatcher?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: PermissionsOnboardingWindow?
    /// Tracks whether the egress dot has ever pulsed red; passed into PrivacySettingsView.
    private var hasPulsedRed: Bool = false

    private var modelObservationTask: Task<Void, Never>?
    private var hudObservationTask: Task<Void, Never>?

    // MARK: - Network Activity Monitor (S3-T3)

    /// Live egress monitor. Started before the status item is created so the
    /// dot badge reflects state from the first frame.
    let networkMonitor = NetworkActivityMonitor()
    private var egressObservationTask: Task<Void, Never>?

    // MARK: - Whisper Glass state

    private let pipelineState = PipelineStateModel()
    /// Held alive for audio level forwarding.
    private var hudController: FloatingHUDWindowController?
    /// Held alive for voice command HUD feedback (S5-UX-1).
    private var voiceCommandHUD: VoiceCommandHUDController?

    // MARK: - Icon tracking (no SwiftUI embedding in button)

    /// The SF Symbol name currently displayed in the status button.
    /// Updated by applyStatusIcon(_:) so applyEgressDot(_:) always composites
    /// over the correct base symbol.
    private var currentIconSymbolName: String = "waveform.and.mic"

    /// The tint color currently applied to the status button, or nil for template
    /// rendering. Restored by applyEgressDot when the dot is removed.
    private var currentTintColor: NSColor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Flush log on abnormal exit
        signal(SIGABRT) { _ in FileLogger.shared.log(.error, "[Crash] SIGABRT received"); exit(1) }
        signal(SIGSEGV) { _ in FileLogger.shared.log(.error, "[Crash] SIGSEGV received"); exit(1) }
        signal(SIGILL) { _ in FileLogger.shared.log(.error, "[Crash] SIGILL received"); exit(1) }
        NSSetUncaughtExceptionHandler { exception in
            FileLogger.shared.log(
                .error,
                "[Crash] Uncaught exception: \(exception.name.rawValue) — \(exception.reason ?? "no reason")"
            )
        }

        let alreadyRunning = NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? ""
        )
        if alreadyRunning.count > 1 {
            alreadyRunning.first(where: { $0 != NSRunningApplication.current })?
                .activate(options: .activateIgnoringOtherApps)
            NSApp.terminate(nil)
            return
        }

        NSApp.setActivationPolicy(.accessory) // hide from Dock

        // Start network monitoring immediately. EgressAuditor is wired after monitor starts.
        networkMonitor.startMonitoring()
        EgressAuditor.shared.configure(monitor: networkMonitor)
        startEgressObservation()

        // Guard: show onboarding window when any required permission is missing.
        // Menu bar item is suppressed until onboarding completes.
        let requiredGranted = permissions.status(for: .microphone) == .granted
            && AXIsProcessTrusted()

        if !requiredGranted {
            showOnboarding()
        } else {
            setupStatusItem()
            setupPopover()
            checkPermissionsAndStart()
            checkModelPresence()
        }

        // Sync SMAppService state with stored preference
        syncLaunchAtLogin(settingsManager.launchAtLogin)
    }

    func applicationWillTerminate(_ notification: Notification) {
        networkMonitor.stopMonitoring()
        try? AppDatabase.shared.pool.close()
        egressObservationTask?.cancel()
    }

    // MARK: - Launch at Login

    func syncLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            FileLogger.shared.log(.warn, "[LaunchAtLogin] SMAppService error: \(error)")
        }
    }

    // MARK: - Onboarding

    private func showOnboarding() {
        let window = PermissionsOnboardingWindow(permissions: permissions) { [weak self] in
            guard let self else { return }
            self.onboardingWindow = nil
            self.setupStatusItem()
            self.setupPopover()
            self.checkPermissionsAndStart()
            self.checkModelPresence()
        }
        onboardingWindow = window
        window.show()
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem?.button else { return }

        button.image = NSImage(systemSymbolName: "waveform.and.mic",
                               accessibilityDescription: "WhisKey")
        button.image?.isTemplate = true

        button.action = #selector(statusItemClicked)
        button.target = self
        applyStatusIcon(.idle)
    }

    // S3-T4: .handsFree added for hands-free recording state (steady orange mic.badge.xmark).
    // No animation for this state — it is a stable indefinite mode.
    private enum IconState { case idle, recording, handsFree, processing, error }

    /// Updates the status button directly via NSImage + CABasicAnimation.
    /// No NSHostingView or SwiftUI embedding — preserves the popover coordinate fix from PR #28.
    private func applyStatusIcon(_ state: IconState) {
        guard let button = statusItem?.button else { return }

        // Clear any previous pulse animation first.
        button.layer?.removeAnimation(forKey: "whiskey.pulse")

        switch state {
        case .idle:
            currentIconSymbolName = "waveform.and.mic"
            currentTintColor = nil
            button.image = NSImage(systemSymbolName: currentIconSymbolName,
                                   accessibilityDescription: "WhisKey")
            button.image?.isTemplate = true
            button.contentTintColor = nil
            button.setAccessibilityLabel("WhisKey")

        case .recording:
            // PTT: pulsing red mic.fill per S3-C2 spec table 4.1.
            currentIconSymbolName = "mic.fill"
            currentTintColor = .systemRed
            button.image = NSImage(systemSymbolName: currentIconSymbolName,
                                   accessibilityDescription: "Recording")
            button.image?.isTemplate = false
            button.contentTintColor = .systemRed
            button.setAccessibilityLabel("WhisKey \u{2013} Push-to-Talk Recording")
            button.wantsLayer = true
            // Respect reduce-motion preference.
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                let pulse = CABasicAnimation(keyPath: "opacity")
                pulse.fromValue = 1.0
                pulse.toValue = 0.35
                pulse.duration = 0.75
                pulse.autoreverses = true
                pulse.repeatCount = .infinity
                pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                button.layer?.add(pulse, forKey: "whiskey.pulse")
            }

        case .handsFree:
            // Hands-free: steady orange mic.badge.xmark. No pulse (stable indefinite state).
            // mic.badge.xmark available macOS 14+. systemOrange is a semantic color.
            currentIconSymbolName = "mic.badge.xmark"
            currentTintColor = .systemOrange
            button.image = NSImage(systemSymbolName: currentIconSymbolName,
                                   accessibilityDescription: "Hands-Free Recording")
            button.image?.isTemplate = false
            button.contentTintColor = .systemOrange
            button.setAccessibilityLabel("WhisKey \u{2013} Hands-Free Recording")

        case .processing:
            currentIconSymbolName = "waveform"
            currentTintColor = nil
            button.image = NSImage(systemSymbolName: currentIconSymbolName,
                                   accessibilityDescription: "Transcribing")
            button.image?.isTemplate = true
            button.contentTintColor = nil
            button.setAccessibilityLabel("WhisKey \u{2013} Transcribing")

        case .error:
            currentIconSymbolName = "exclamationmark.triangle"
            currentTintColor = .systemOrange
            button.image = NSImage(systemSymbolName: currentIconSymbolName,
                                   accessibilityDescription: "WhisKey Error")
            button.image?.isTemplate = true
            button.contentTintColor = .systemOrange
            button.setAccessibilityLabel("WhisKey \u{2013} Error")
        }

        // Re-apply the egress dot over the freshly set icon so the badge is never lost
        // when a state transition happens while egress monitoring is active.
        applyEgressDot(networkMonitor.egressState)
    }

    // MARK: - Egress Dot Badge (S3-T3)

    /// Composites a small colored dot onto the current base SF Symbol and sets the
    /// result as button.image. No SwiftUI — pure NSImage drawing.
    ///
    /// Called from startEgressObservation() whenever egressState changes, and also
    /// at the end of applyStatusIcon(_:) to keep the dot in sync after state transitions.
    private func applyEgressDot(_ state: EgressState) {
        guard let button = statusItem?.button else { return }

        let dotColor: NSColor? = switch state {
        case .local:       .systemGreen
        case .audited:     .secondaryLabelColor
        case .unexpected:  .systemRed
        case .unavailable: nil
        }

        if let dotColor {
            // Composite: SF Symbol + dot in bottom-right quadrant.
            // isTemplate = false so AppKit does not re-tint the composite; the dot
            // must render in its semantic color, not the system accent.
            let size = NSSize(width: 18, height: 18)
            let composite = NSImage(size: size, flipped: false) { bounds in
                NSImage(systemSymbolName: self.currentIconSymbolName,
                        accessibilityDescription: nil)?
                    .draw(in: bounds)
                let dotRect = NSRect(x: bounds.maxX - 6, y: 0, width: 6, height: 6)
                dotColor.setFill()
                NSBezierPath(ovalIn: dotRect).fill()
                return true
            }
            composite.isTemplate = false
            button.image = composite
            // Clear tint so the composited dot colour is not overridden by AppKit tinting.
            button.contentTintColor = nil
        } else {
            // No dot — restore the plain template image with its current tint.
            button.image = NSImage(systemSymbolName: currentIconSymbolName,
                                   accessibilityDescription: "WhisKey")
            button.image?.isTemplate = (currentTintColor == nil)
            button.contentTintColor = currentTintColor
        }
    }

    /// Polls `networkMonitor.egressState` at 500 ms intervals and updates the
    /// menu bar dot badge and accessibility label accordingly.
    ///
    /// @Observable does not bridge to async streams natively on macOS 14, so a
    /// polling loop is used — identical to the S3-T3 approach on the feature branch.
    private func startEgressObservation() {
        egressObservationTask = Task { [weak self] in
            var lastState: EgressState?
            while !Task.isCancelled {
                guard let self else { return }
                let state = self.networkMonitor.egressState
                if state != lastState {
                    lastState = state
                    self.applyEgressDot(state)
                    if state == .unexpected { self.hasPulsedRed = true }
                    // Update accessibility label for idle/hands-free states.
                    // Recording and processing states own their own labels.
                    if let button = self.statusItem?.button {
                        switch state {
                        case .local:
                            button.setAccessibilityLabel("WhisKey \u{2013} Local mode, no egress")
                        case .audited:
                            button.setAccessibilityLabel("WhisKey \u{2013} Cloud provider active")
                        case .unexpected:
                            button.setAccessibilityLabel("WhisKey \u{2013} Warning: unexpected egress detected")
                        case .unavailable:
                            break // Leave whatever the icon state set.
                        }
                    }
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    // MARK: - State Transitions

    private func transitionToRecording() {
        applyStatusIcon(.recording)
        pipelineState.recordingState = .recording
    }

    /// Transitions to hands-free recording state.
    /// Per S3-C2 spec section 6.3: post a VoiceOver announcement on entry.
    private func transitionToHandsFree() {
        applyStatusIcon(.handsFree)
        pipelineState.recordingState = .handsFreeRecording
        NSAccessibility.post(
            element: statusItem?.button as Any,
            notification: .announcementRequested,
            userInfo: [
                NSAccessibility.NotificationUserInfoKey.announcement:
                    "Hands-free recording started. Tap the hotkey to stop.",
                NSAccessibility.NotificationUserInfoKey.priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
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
        // Match MenuBarView's declared frame exactly so NSHostingController reports
        // the same preferredContentSize and no post-show resize/reanchor occurs.
        popover.contentSize = NSSize(width: 320, height: 480)
        popover.behavior = .transient
        let view = MenuBarView(
            historyStore: pipeline.historyStore,
            modelManager: modelManager,
            pipeline: pipeline,
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
            // NSStatusBarButton is flipped (y=0 at visual top) and has a -4.5pt y offset
            // in its parent window. Passing `button` as the anchor view for popover.show
            // causes AppKit to mis-convert the flipped coordinate system through that offset,
            // landing the popover on top of the icon regardless of preferredEdge.
            //
            // Fix: convert button.bounds into the window's NON-FLIPPED contentView space
            // (confirmed isFlipped=false via debug). That gives AppKit an unambiguous rect
            // in a known coordinate system. .minY on a non-flipped view = visual bottom =
            // below the menu bar = correct drop direction.
            if let contentView = button.window?.contentView {
                let rectInContentView = button.convert(button.bounds, to: contentView)
                popover.show(relativeTo: rectInContentView, of: contentView, preferredEdge: .minY)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
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

        let settingsView = SettingsView(
            settings: settingsManager,
            modelManager: modelManager,
            networkMonitor: networkMonitor,
            hasPulsedRed: .constant(hasPulsedRed),
            bindingStore: bindingStore,
            toneProfileStore: toneProfileStore
        )
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
        alert.informativeText = "WhisKey needs a Whisper model to transcribe speech.\n\n"
            + "Open Settings → Models and download at least one ASR model to get started."
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

    // swiftlint:disable:next function_body_length
    private func startHotkey() {
        let flog = FileLogger.shared
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        flog.log(.info, "WhisKey started (build: \(build)). Log: \(flog.logFilePath)")

        // Apply persisted settings to pipeline (actor-isolated setters require await).
        let langHint = settingsManager.languageHint
        let cleanupProfile = settingsManager.cleanupProfile
        let svc = appContextService

        // Feature 1.3: Start active-app profile service and inject into pipeline.
        appContextService.start()

        // Wire pipeline callbacks (nonisolated lock-backed; no await needed).
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
            Task { @MainActor [weak self] in
                self?.handlePipelineError(error)
            }
        }

        // Push actor-isolated configuration via async setters.
        let toneStore = toneProfileStore
        Task {
            await pipeline.setLanguageHint(langHint)
            await pipeline.setCleanupProfile(cleanupProfile)
            await pipeline.setAppContextService(svc)
            await pipeline.setToneProfileStore(toneStore)
            // S1-T1: Wire the snippet store so trigger expansion is applied on every
            // transcription.  Without this call, snippetStore remains nil and
            // applySnippetExpansion returns the original text on every invocation.
            await pipeline.setSnippetStore(SnippetStore.shared)
        }

        // Wire floating HUD (legacy waveform overlay — kept for recording visual feedback).
        let hud = FloatingHUDWindowController(pipeline: pipeline, settingsManager: settingsManager)
        hudController = hud
        hud.setVisible(settingsManager.hudEnabled)
        voiceCommandHUD = VoiceCommandHUDController()
        pipelineState.subscribe(toAudioLevel: pipeline.audioLevelPublisher)

        // P1: Subscribe HUD caption strip to streaming partial transcripts.
        hud.subscribeToPartials(pipeline.partialTranscriptPublisher.eraseToAnyPublisher())

        // P2: Clear the caption strip after injection, honouring the user's linger setting.
        // The closure reads settingsManager.previewLingerMode live at call time, so
        // no observation task is needed — changes take effect on the next transcription.
        pipeline.onPreviewClear = { [weak hud, weak settingsManager] in
            Task { @MainActor in
                let mode = settingsManager?.previewLingerMode ?? .linger(seconds: 2)
                hud?.handlePreviewClear(mode: mode)
            }
        }

        // S1-T3: Drive HUD animation and state transition from onMicOpen —
        // this fires inside startRecording() AFTER AVAudioEngine.start() returns,
        // guaranteeing the mic is open before any visual recording feedback appears.
        pipeline.onMicOpen = { [weak self, weak hud] in
            flog.log(.info, "[TIMING] Mic ready — HUD animating")
            Task { @MainActor [weak self, weak hud] in
                self?.transitionToRecording()
                hud?.recordingDidStart()
            }
        }

        // Wire hotkey to pipeline + state model.
        // S1-T3: HUD animation is sequenced AFTER mic is confirmed open.
        // onMicOpen fires from inside startRecording() once AVAudioEngine.start() returns.
        // This eliminates the ~100-150 ms leading-word dropout caused by the old pattern
        // of calling hud.recordingDidStart() synchronously before the async Task ran.
        hotkey.onStartRecording = { [weak self, weak hud] in
            flog.log(.info, "[TIMING] Hotkey down")
            Task {
                await self?.pipeline.startRecording()
                // onMicOpen fires from inside startRecording() — HUD wires to it below.
                // transitionToRecording and recordingDidStart are driven via onMicOpen.
            }
        }
        hotkey.onStopRecording = { [weak self, weak hud] in
            guard let self else { return }
            flog.log(.info, "[TIMING] Hotkey up")
            flog.log(.info, "Hotkey up — running transcription.")
            self.transitionToProcessing()
            hud?.recordingDidStop()
            self.transcriptionTask?.cancel()
            self.transcriptionTask = Task {
                await self.pipeline.stopAndTranscribe()
            }
        }
        // S3-T4 / S4-T4: Hands-free callbacks — routed through HotkeyDispatcher.
        // dispatcher.onHandsFreeTranscription is set below after the dispatcher is created.

        // Sync hotkey settings from persisted values at launch.
        hotkey.disambiguationWindowMs = settingsManager.disambiguationWindowMs
        hotkey.handsFreeEnabled = settingsManager.handsFreeEnabled

        // S4-T4: Create the dispatcher and wire all four action callbacks.
        let dispatcher = HotkeyDispatcher(bindingStore: bindingStore, hotkeyManager: hotkey)
        hotkeyDispatcher = dispatcher

        dispatcher.onDefaultTranscription = nil // PTT driven by hotkey.onStartRecording above.

        // S1-T4: Hands-free path uses mic-first ordering via a dedicated Task.
        // onMicOpen (wired above) fires transitionToRecording; for the hands-free path
        // we need transitionToHandsFree instead. We sequence this by awaiting
        // startRecording() and reading the result synchronously on MainActor,
        // then transitioning on MainActor inside the same Task — mic is already open.
        dispatcher.onHandsFreeTranscription = { [weak self, weak hud] in
            flog.log(.info, "[TIMING] Hotkey down")
            flog.log(.info, "Hands-free hotkey — hands-free recording started.")
            Task { [weak self, weak hud] in
                await self?.pipeline.startRecording()
                // At this point mic is open (startRecording has returned).
                // onMicOpen fires inside startRecording and calls transitionToRecording;
                // override with hands-free state on MainActor immediately after.
                await MainActor.run { [weak self, weak hud] in
                    flog.log(.info, "[TIMING] Mic ready — HUD animating")
                    self?.transitionToHandsFree()
                    hud?.recordingDidStart()
                }
            }
        }

        dispatcher.onOpenPopover = { [weak self] in
            flog.log(.info, "openPopover hotkey fired.")
            self?.statusItemClicked()
        }

        dispatcher.onInjectLastTranscription = { [weak self] in
            guard let self else { return }
            flog.log(.info, "injectLastTranscription hotkey fired.")
            Task {
                guard let entry = try? await self.pipeline.historyStore.fetchRecent(limit: 1).first else {
                    flog.log(.warn, "injectLastTranscription: history is empty.")
                    return
                }
                await self.pipeline.reinjectText(entry.text)
            }
        }

        // Wire the hands-free stop path directly on HotkeyManager (unchanged from S3-T4).
        hotkey.onHandsFreeStop = { [weak self, weak hud] in
            guard let self else { return }
            flog.log(.info, "Hands-free stop tap — running transcription.")
            self.transitionToProcessing()
            hud?.recordingDidStop()
            self.transcriptionTask?.cancel()
            self.transcriptionTask = Task {
                await self.pipeline.stopAndTranscribe()
            }
        }

        // Apply all four bindings at launch.
        dispatcher.syncBindings()

        // Live-sync hotkey settings whenever UserDefaults change (slider/toggle in Settings).
        // The closure NotificationCenter invokes is `@Sendable`, so all reads of
        // `@MainActor`-isolated properties (settingsManager, bindingStore,
        // hotkey.handsFreeEnabled, etc.) must hop through a MainActor Task to
        // satisfy strict-concurrency. Sprint 4 / S4-T3.
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.hotkey.disambiguationWindowMs = self.settingsManager.disambiguationWindowMs
                self.hotkey.handsFreeEnabled = self.settingsManager.handsFreeEnabled
                // S4-T4: All four bindings are now re-synced via the dispatcher.
                self.hotkeyDispatcher?.syncBindings()
            }
        }

        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            let enabled = await MainActor.run { self.settingsManager.llmEnabled }
            guard enabled else { return }
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

        startModelObservation()
        startHUDObservation()
    }

    private func startHUDObservation() {
        hudObservationTask?.cancel()
        hudObservationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var lastValue = self.settingsManager.hudEnabled
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { break }
                let current = self.settingsManager.hudEnabled
                guard current != lastValue else { continue }
                lastValue = current
                self.hudController?.setVisible(current)
            }
        }
    }

    /// Watch `settingsManager.activeModelID` and reload WhisperBridge whenever it changes.
    private func startModelObservation() {
        modelObservationTask?.cancel()
        modelObservationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var lastModelID = self.settingsManager.activeModelID
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { break }
                let current = self.settingsManager.activeModelID
                guard current != lastModelID else { continue }
                lastModelID = current
                guard let modelID = current,
                      let model = ModelManager.availableModels.first(where: { $0.id == modelID })
                else { continue }
                await self.pipeline.reloadWhisperModel(filename: model.filename)
                FileLogger.shared.log(.info, "WhisperBridge reloaded: \(model.filename)")
            }
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
