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
/// Typical usage:
/// ```swift
/// let pipeline = TranscriptionPipeline()
/// pipeline.startRecording()           // called from hotkey down
/// let result = try await pipeline.stopAndTranscribe()  // called from hotkey up
/// ```
public final class TranscriptionPipeline: @unchecked Sendable {

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
    private let historyStore: HistoryStore
    private let settings: SettingsManager

    // MARK: - Configuration

    /// BCP-47 language hint passed to Whisper. nil = auto-detect.
    public var languageHint: String?

    /// LLM post-processing backend. Defaults to LlamaCppProvider; falls back to
    /// PassthroughProvider at runtime when the GGUF model file is absent.
    public var llmProvider: any LLMProvider = LlamaCppProvider()

    /// Cleanup profile applied to every transcription.
    public var cleanupProfile: CleanupProfile = CleanupProfile()

    /// Context service used to read the frontmost application before injection.
    private let contextService = ContextService()

    // MARK: - Audio Level

    /// Normalized RMS audio level (0.0–1.0) forwarded from AudioCaptureService.
    /// Subscribe from UI layers for real-time waveform visualization.
    public var audioLevelPublisher: AnyPublisher<Float, Never> {
        audioCapture.audioLevelPublisher.eraseToAnyPublisher()
    }

    // MARK: - State

    private var isRecording = false

    // MARK: - Callbacks

    /// Called on the main thread when a transcription result is ready.
    public var onTranscriptionReady: ((TranscriptionResult) -> Void)?

    /// Called on the main thread when any pipeline error occurs.
    public var onError: ((Error) -> Void)?

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
    public func startRecording() {
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
            DispatchQueue.main.async { [weak self] in
                self?.onError?(mapped)
            }
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
    public func stopAndTranscribe() async -> TranscriptionResult? {
        guard isRecording else {
            logger.warning("stopAndTranscribe called while not recording — ignored.")
            return nil
        }

        isRecording = false
        let pcmSamples = audioCapture.stopCapture()
        let flog = FileLogger.shared
        flog.log(.info, "Recording stopped. Captured \(pcmSamples.count) samples.")
        logger.info("Recording stopped. Captured \(pcmSamples.count) samples.")

        guard !pcmSamples.isEmpty else {
            flog.log(.warn, "No audio samples captured — check Microphone permission.")
            logger.warning("No audio samples captured; skipping transcription.")
            // Fix 4: Ensure capture flags are fully cleared on this error path.
            audioCapture.reset()
            return nil
        }

        // Snapshot the focused AX element NOW — before transcription latency causes focus to change.
        let capturedAXElement: AXUIElement? = await MainActor.run {
            guard AXIsProcessTrusted() else { return nil }
            let sysWide = AXUIElementCreateSystemWide()
            var ref: CFTypeRef?
            AXUIElementCopyAttributeValue(sysWide, kAXFocusedUIElementAttribute as CFString, &ref)
            return ref.map { $0 as! AXUIElement }  // swiftlint:disable:this force_cast
        }

        guard let result = await runTranscription(pcmSamples: pcmSamples) else { return nil }

        guard !result.text.isEmpty,
              !Self.whisperNoiseTokens.contains(result.text) else {
            logger.info("Suppressing output — blank or noise-only transcription: \"\(result.text)\"")
            return result
        }

        let injectionContext = await MainActor.run { contextService.currentContext() }
        let llmEnabled = await MainActor.run { settings.llmEnabled }
        let textToInject = llmEnabled
            ? await applyLLMCleanup(rawText: result.text, context: injectionContext)
            : result.text

        await dispatchOutput(text: textToInject, capturedElement: capturedAXElement)
        await persistAndNotify(result: result, textToInject: textToInject, bundleID: injectionContext.activeAppBundleID)
        return result
    }

    private func runTranscription(pcmSamples: [Float]) async -> TranscriptionResult? {
        let flog = FileLogger.shared
        flog.log(.info, "Starting Whisper transcription (\(pcmSamples.count) samples)...")
        do {
            let result = try await whisper.transcribe(pcm: pcmSamples, languageHint: languageHint)
            flog.log(.info, "Whisper returned: \"\(result.text)\"")
            logger.info("Transcription complete: \"\(result.text)\" [\(result.language), \(result.durationMs)ms]")
            return result
        } catch {
            flog.log(.error, "Whisper error: \(error.localizedDescription)")
            logger.error("Transcription error: \(error.localizedDescription)")
            await MainActor.run { onError?(PipelineError.transcriptionError(error)) }
            return nil
        }
    }

    private func applyLLMCleanup(rawText: String, context: InjectionContext) async -> String {
        var profile = cleanupProfile
        if profile.toneStyle == .casual && !profile.rawMode {
            profile = CleanupProfile(
                removeFillers: profile.removeFillers,
                addPunctuation: profile.addPunctuation,
                toneStyle: contextService.suggestedToneStyle(for: context.activeAppBundleID),
                rawMode: profile.rawMode
            )
        }
        do {
            let cleaned = try await llmProvider.cleanup(rawTranscript: rawText, context: context, profile: profile)
            if cleaned != rawText {
                logger.info("LLM cleanup applied. Original: \"\(rawText)\" → Cleaned: \"\(cleaned)\"")
            }
            return cleaned
        } catch {
            logger.error("LLM cleanup threw an error: \(error.localizedDescription) — injecting raw transcript.")
            FileLogger.shared.log(
                .warn,
                "Pipeline: LLM cleanup failed (\(error.localizedDescription)); falling back to raw transcript."
            )
            await MainActor.run { [weak self] in
                self?.onError?(PipelineError.llmCleanupFailed(error))
            }
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

    private func persistAndNotify(result: TranscriptionResult, textToInject: String, bundleID: String) async {
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
