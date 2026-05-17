// swiftlint:disable file_length
import AppKit
@preconcurrency import ApplicationServices
import Combine
import Foundation
import os.log

private let logger = Logger(subsystem: "com.whiskey.app", category: "TranscriptionPipeline")

/// Errors produced by the pipeline.
///
/// Cases are categorised so the UI layer can decide presentation (notification,
/// silent log, status-bar badge) without doing brittle string-matching on the
/// underlying message. See `severity` and `isUserActionable`.
public enum PipelineError: Error, LocalizedError {
    /// `startRecording` was invoked while a session was already in flight.
    /// Internal state; not user-actionable; never surface as a notification.
    case alreadyRecording

    /// `stopAndTranscribe` was invoked while no session was active.
    /// Internal state; not user-actionable; never surface as a notification.
    case notRecording

    /// Audio capture machinery (AVFoundation / CoreAudio) failed to start or run.
    /// Distinct from `microphonePermissionDenied` — this is a device/engine
    /// error, not a permission problem.
    case captureError(Error)

    /// Microphone access was denied or revoked at the system level.
    /// User-actionable: prompt them to open System Settings.
    case microphonePermissionDenied

    /// Whisper transcription produced an error or returned no usable result.
    case transcriptionError(Error)

    /// Text injection into the focused window was deliberately skipped.
    /// User-visible reason describes why (no AX permission, no focused field, etc.).
    case injectionSkipped(String)

    /// CGEventTap could not be installed — Input Monitoring permission missing.
    case hotkeyUnavailable(String)

    /// LLM cleanup failed but raw transcript was injected. Informational only.
    case llmCleanupFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "Recording is already in progress."
        case .notRecording:
            return "No recording session is active."
        case .captureError(let err):
            return "Audio capture failed: \(err.localizedDescription)"
        case .microphonePermissionDenied:
            return "Microphone access is required. Grant permission in System Settings → Privacy & Security → Microphone."
        case .transcriptionError(let err):
            return "Transcription failed: \(err.localizedDescription)"
        case .injectionSkipped(let reason):
            return "Text injection skipped: \(reason)"
        case .hotkeyUnavailable(let reason):
            return "Hotkey unavailable: \(reason)"
        case .llmCleanupFailed(let err):
            return "LLM cleanup failed: \(err.localizedDescription) — raw transcript was used."
        }
    }

    /// Severity classification used by callers to pick a presentation channel.
    public enum Severity: Sendable {
        /// Internal state transition; log only.
        case info
        /// Non-fatal degradation (e.g. LLM cleanup fell back to raw text).
        case warning
        /// User-actionable failure that should be surfaced via a notification.
        case error
    }

    public var severity: Severity {
        switch self {
        case .alreadyRecording, .notRecording:
            return .info
        case .injectionSkipped, .llmCleanupFailed:
            return .warning
        case .captureError, .microphonePermissionDenied,
             .transcriptionError, .hotkeyUnavailable:
            return .error
        }
    }

    /// True when the user can take a concrete remediation step
    /// (grant a permission, free disk space, etc.).
    public var isUserActionable: Bool {
        switch self {
        case .microphonePermissionDenied, .hotkeyUnavailable, .injectionSkipped:
            return true
        case .captureError, .transcriptionError, .llmCleanupFailed,
             .alreadyRecording, .notRecording:
            return false
        }
    }
}

/// Async orchestrator wiring AudioCaptureService → WhisperBridge → TextInjector.
///
/// `TranscriptionPipeline` is a Swift actor: all mutable state (`isRecording`) is
/// automatically protected by actor isolation. Callers must `await` actor-isolated
/// methods (`startRecording`, `stopAndTranscribe`, `warmUpLLM`) from outside the actor.
///
/// Typical usage:
/// ```swift
/// let pipeline = TranscriptionPipeline()
/// await pipeline.startRecording()           // called from hotkey down
/// let result = await pipeline.stopAndTranscribe()  // called from hotkey up
/// ```
public actor TranscriptionPipeline {

    // MARK: - Constants

    /// Whisper special-token strings that indicate no real speech was detected.
    /// Results matching these tokens are suppressed — nothing is injected or typed.
    private static let whisperNoiseTokens: Set<String> = [
        "[BLANK_AUDIO]", "[MUSIC]", "[NOISE]", "[INAUDIBLE]"
    ]

    // MARK: - Dependencies

    private let audioCapture: AudioCaptureService
    private let whisper: WhisperBridge
    private let injector: TextInjector
    private let permissions: PermissionsManager
    public nonisolated let historyStore: HistoryStore
    private let settings: SettingsManager

    // MARK: - Configuration

    /// BCP-47 language hint passed to Whisper. nil = auto-detect.
    /// Actor-isolated; use `setLanguageHint(_:)` to update from outside the actor.
    public var languageHint: String?

    /// LLM post-processing backend. Defaults to LlamaCppProvider; falls back to
    /// PassthroughProvider at runtime when the GGUF model file is absent.
    /// Actor-isolated; use `setLLMProvider(_:)` to update from outside the actor.
    public var llmProvider: any LLMProvider = LlamaCppProvider()

    /// Cleanup profile applied to every transcription.
    /// Actor-isolated; use `setCleanupProfile(_:)` to update from outside the actor.
    public var cleanupProfile: CleanupProfile = CleanupProfile()

    /// Context service used to read the frontmost application before injection.
    private let contextService = ContextService()

    /// Active-app profile service (Feature 1.3). Injected from `AppDelegate`.
    /// `nil` preserves pre-Sprint-1 behaviour for any caller that does not supply it.
    /// Actor-isolated; use `setAppContextService(_:)` to update from outside the actor.
    public var appContextService: AppContextService?

    // MARK: - Audio Level

    /// Normalized RMS audio level (0.0–1.0) forwarded from AudioCaptureService.
    /// Subscribe from UI layers for real-time waveform visualization.
    /// `nonisolated` because `audioCapture` is a `let` stored property — actors
    /// expose `let` properties nonisolated by default, so this computed property
    /// is safe to call without `await`.
    public nonisolated var audioLevelPublisher: AnyPublisher<Float, Never> {
        audioCapture.audioLevelPublisher.eraseToAnyPublisher()
    }

    // MARK: - State

    private var isRecording = false

    // MARK: - Callbacks (lock-backed for nonisolated access)

    /// Lock protecting both callback closures so they can be read/written
    /// from any concurrency domain without `nonisolated(unsafe)`.
    private let _callbackLock = OSAllocatedUnfairLock<
        (onReady: (@Sendable (TranscriptionResult) -> Void)?,
         onError: (@Sendable (Error) -> Void)?)
    >(initialState: (onReady: nil, onError: nil))

    /// Called on the main thread when a transcription result is ready.
    /// Backed by a lock so it can be assigned from any context without data races.
    public nonisolated var onTranscriptionReady: (@Sendable (TranscriptionResult) -> Void)? {
        get { _callbackLock.withLock { $0.onReady } }
        set { _callbackLock.withLock { $0.onReady = newValue } }
    }

    /// Called on the main thread when any pipeline error occurs.
    /// Backed by a lock so it can be assigned from any context without data races.
    public nonisolated var onError: (@Sendable (Error) -> Void)? {
        get { _callbackLock.withLock { $0.onError } }
        set { _callbackLock.withLock { $0.onError = newValue } }
    }

    // MARK: - Init

    // @MainActor required: SettingsManager default value is @MainActor-isolated.
    // TranscriptionPipeline is always constructed on the main thread (AppDelegate).
    @MainActor
    public init(
        audioCapture: AudioCaptureService = AudioCaptureService(),
        whisper: WhisperBridge = .shared,
        injector: TextInjector = TextInjector(),
        permissions: PermissionsManager = PermissionsManager(),
        historyStore: HistoryStore = HistoryStore(),
        settings: SettingsManager = SettingsManager()
    ) {
        self.audioCapture = audioCapture
        self.whisper = whisper
        self.injector = injector
        self.permissions = permissions
        self.historyStore = historyStore
        self.settings = settings
    }

    // MARK: - Actor-isolated configuration setters

    /// Sets the BCP-47 language hint forwarded to Whisper. Pass `nil` for auto-detect.
    public func setLanguageHint(_ value: String?) {
        self.languageHint = value
    }

    /// Replaces the LLM post-processing backend.
    public func setLLMProvider(_ value: any LLMProvider) {
        self.llmProvider = value
    }

    /// Replaces the cleanup profile applied to every transcription.
    public func setCleanupProfile(_ value: CleanupProfile) {
        self.cleanupProfile = value
    }

    /// Sets the active-app profile service used to resolve per-app settings.
    public func setAppContextService(_ value: AppContextService?) {
        self.appContextService = value
    }

    /// Convenience setter for both pipeline callbacks in a single actor hop.
    /// Prefer this over setting `onTranscriptionReady` and `onError` separately
    /// when wiring from an `async` context.
    public func setCallbacks(
        onReady: (@Sendable (TranscriptionResult) -> Void)?,
        onError: (@Sendable (Error) -> Void)?
    ) {
        _callbackLock.withLock {
            $0.onReady = onReady
            $0.onError = onError
        }
    }

    // MARK: - Public API

    /// Preload the LLM model in the background so first-use latency is eliminated.
    public func warmUpLLM() async {
        await llmProvider.warmUp()
    }

    /// Begin audio capture. Call when the hotkey is pressed.
    ///
    /// On failure, `onError` is invoked on the main thread with a typed
    /// `PipelineError`. When the underlying cause is a denied microphone
    /// permission, the error is surfaced as `.microphonePermissionDenied`
    /// rather than the generic `.captureError` so the UI can prompt the user
    /// to open System Settings. All error paths are mirrored to `FileLogger`.
    public func startRecording() async {
        let flog = FileLogger.shared
        guard !isRecording else {
            logger.warning("startRecording called while already recording — ignored.")
            flog.log(.warn, "Pipeline: startRecording called while already recording (debounced).")
            return
        }

        do {
            try audioCapture.startCapture()
            isRecording = true
            logger.info("Recording started.")
        } catch {
            logger.error("Audio capture failed to start: \(error.localizedDescription)")
            flog.log(.error, "Pipeline: capture failed to start: \(error.localizedDescription)")

            // Fix 4: Reset capture state so both flags are clear on failure.
            audioCapture.reset()

            // Discriminate: permission denied vs. engine error. AVFoundation surfaces
            // microphone-denial as a specific AVError; treat anything else as a
            // generic engine failure so the user gets the right remediation.
            let mapped: PipelineError
            if Self.isMicrophonePermissionError(error) {
                mapped = .microphonePermissionDenied
            } else {
                mapped = .captureError(error)
            }
            await MainActor.run { onError?(mapped) }
        }
    }

    /// Best-effort classifier: returns true when `error` indicates that the
    /// system refused microphone access (as opposed to an engine failure).
    private static func isMicrophonePermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        // AVFoundation surfaces denial via AVAudioSession.ErrorCode on iOS-style APIs;
        // on macOS the same path raises a CoreAudio error whose domain string contains
        // "permission" or "AudioSession". Keep this resilient with a string fallback.
        if nsError.domain.contains("AudioSession") { return true }
        let desc = nsError.localizedDescription.lowercased()
        return desc.contains("permission") || desc.contains("not authorized") || desc.contains("denied")
    }

    /// Stop recording, run transcription, and inject the result into the focused window.
    /// Call when the hotkey is released.
    @discardableResult
    // swiftlint:disable:next function_body_length
    public func stopAndTranscribe() async -> TranscriptionResult? {
        guard isRecording else {
            logger.warning("stopAndTranscribe called while not recording — ignored.")
            return nil
        }

        isRecording = false
        let rawSamples = audioCapture.stopCapture()
        let flog = FileLogger.shared
        flog.log(.info, "Recording stopped. Captured \(rawSamples.count) samples.")
        logger.info("Recording stopped. Captured \(rawSamples.count) samples.")

        guard !rawSamples.isEmpty else {
            flog.log(.warn, "No audio samples captured — check Microphone permission.")
            logger.warning("No audio samples captured; skipping transcription.")
            // Fix 4: Ensure capture flags are fully cleared on this error path.
            audioCapture.reset()
            return nil
        }

        // Feature 1.3: resolve active-app profile once at call start for a stable view.
        // Capture the service reference from actor isolation first, then hop to @MainActor
        // to read the @MainActor-isolated `activeProfile` property.
        let capturedContextService = appContextService
        let profile = await MainActor.run { capturedContextService?.activeProfile }
        let effectiveLangHint = profile?.languageHint ?? languageHint
        let effectiveCleanup = profile?.cleanupProfile ?? cleanupProfile

        // Feature 1.2: energy-based silence trim (pre-Whisper).
        let trimEnabled = await MainActor.run { settings.silenceTrimEnabled }
        let pcmSamples: [Float]
        if trimEnabled {
            let trimmed = SilenceTrimmer.trim(rawSamples)
            if trimmed.isEmpty {
                flog.log(.warn, "SilenceTrimmer: buffer contained < 200 ms of speech — skipping.")
                logger.warning("SilenceTrimmer returned empty buffer; skipping transcription.")
                return nil
            }
            flog.log(.info, "SilenceTrimmer: \(rawSamples.count) → \(trimmed.count) samples.")
            pcmSamples = trimmed
        } else {
            pcmSamples = rawSamples
        }

        // Snapshot the focused AX element NOW — before transcription latency causes focus to change.
        let capturedAXElement: AXUIElement? = await MainActor.run {
            guard AXIsProcessTrusted() else { return nil }
            let sysWide = AXUIElementCreateSystemWide()
            var ref: CFTypeRef?
            AXUIElementCopyAttributeValue(sysWide, kAXFocusedUIElementAttribute as CFString, &ref)
            return ref.map { $0 as! AXUIElement }  // swiftlint:disable:this force_cast
        }

        guard let result = await runTranscription(pcmSamples: pcmSamples, langHint: effectiveLangHint) else {
            return nil
        }

        guard !result.text.isEmpty,
              !Self.whisperNoiseTokens.contains(result.text) else {
            logger.info("Suppressing output — blank or noise-only transcription (\(result.text.count) chars)")
            return result
        }

        // Feature 1.2: filler scrubber (post-Whisper, pre-LLM).
        let scrubEnabled = await MainActor.run { settings.fillerScrubberEnabled }
        let scrubbed: String
        if scrubEnabled {
            let cleaned = FillerScrubber.scrub(result.text)
            if cleaned != result.text { flog.log(.info, "FillerScrubber applied.") }
            scrubbed = cleaned
        } else {
            scrubbed = result.text
        }

        let injectionContext = await MainActor.run { contextService.currentContext() }
        let llmEnabled = await MainActor.run { settings.llmEnabled }
        let textToInject = llmEnabled
            ? await applyLLMCleanup(rawText: scrubbed, context: injectionContext, profile: effectiveCleanup)
            : scrubbed

        await dispatchOutput(text: textToInject, capturedElement: capturedAXElement)
        await persistAndNotify(
            result: result,
            textToInject: textToInject,
            bundleID: injectionContext.activeAppBundleID
        )
        return result
    }

    private func runTranscription(pcmSamples: [Float], langHint: String?) async -> TranscriptionResult? {
        let flog = FileLogger.shared
        flog.log(.info, "Starting Whisper transcription (\(pcmSamples.count) samples)...")
        do {
            let result = try await whisper.transcribe(pcm: pcmSamples, languageHint: langHint)
            flog.log(.info, "Whisper returned \(result.text.count) chars [\(result.language ?? "auto")]")
            logger.info("Transcription complete: \(result.text.count) chars [\(result.language ?? "auto"), \(result.durationMs)ms]")
            return result
        } catch {
            flog.log(.error, "Whisper error: \(error.localizedDescription)")
            logger.error("Transcription error: \(error.localizedDescription)")
            await MainActor.run { onError?(PipelineError.transcriptionError(error)) }
            return nil
        }
    }

    private func applyLLMCleanup(
        rawText: String,
        context: InjectionContext,
        profile: CleanupProfile
    ) async -> String {
        var resolvedProfile = profile
        if resolvedProfile.toneStyle == .casual && !resolvedProfile.rawMode {
            resolvedProfile = CleanupProfile(
                removeFillers: resolvedProfile.removeFillers,
                addPunctuation: resolvedProfile.addPunctuation,
                toneStyle: contextService.suggestedToneStyle(for: context.activeAppBundleID),
                rawMode: resolvedProfile.rawMode
            )
        }
        do {
            let cleaned = try await llmProvider.cleanup(
                rawTranscript: rawText,
                context: context,
                profile: resolvedProfile
            )
            if cleaned != rawText {
                logger.info("LLM cleanup applied. \(rawText.count) → \(cleaned.count) chars")
            }
            return cleaned
        } catch {
            logger.error("LLM cleanup threw an error: \(error.localizedDescription) — injecting raw transcript.")
            FileLogger.shared.log(
                .warn,
                "Pipeline: LLM cleanup failed (\(error.localizedDescription)); falling back to raw transcript."
            )
            await MainActor.run { onError?(PipelineError.llmCleanupFailed(error)) }
            return rawText
        }
    }

    private func dispatchOutput(text: String, capturedElement: AXUIElement?) async {
        let mode = await MainActor.run { settings.outputMode }
        switch mode {
        case .activeWindow:
            await injector.inject(text, capturedElement: capturedElement)
        case .clipboard:
            await clipboardOnly(text)
        case .both:
            await injector.inject(text, capturedElement: capturedElement)
            await clipboardOnly(text)
        }
    }

    /// Writes `text` to the system clipboard without simulating Cmd-V or restoring
    /// prior clipboard contents. Called when the output mode is `.clipboard` or `.both`.
    @MainActor
    private func clipboardOnly(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    private func persistAndNotify(
        result: TranscriptionResult,
        textToInject: String,
        bundleID: String
    ) async {
        let entry = HistoryEntry.from(result: result, cleanedText: textToInject, appBundleID: bundleID)
        do {
            try await historyStore.insert(entry)
        } catch {
            logger.error("Failed to persist history entry: \(error.localizedDescription)")
            FileLogger.shared.log(
                .error,
                "Pipeline: failed to persist history entry: \(error.localizedDescription)"
            )
        }
        await MainActor.run { onTranscriptionReady?(result) }
    }
}
