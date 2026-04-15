import Foundation
import os.log

private let logger = Logger(subsystem: "com.whiskey.app", category: "TranscriptionPipeline")

/// Errors produced by the pipeline.
public enum PipelineError: Error, LocalizedError {
    case alreadyRecording
    case notRecording
    case captureError(Error)
    case transcriptionError(Error)
    case injectionSkipped(String)

    public var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "Recording is already in progress."
        case .notRecording:
            return "No recording session is active."
        case .captureError(let err):
            return "Audio capture failed: \(err.localizedDescription)"
        case .transcriptionError(let err):
            return "Transcription failed: \(err.localizedDescription)"
        case .injectionSkipped(let reason):
            return "Text injection skipped: \(reason)"
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

    // MARK: - Dependencies

    private let audioCapture: AudioCaptureService
    private let whisper: WhisperBridge
    private let injector: TextInjector
    private let permissions: PermissionsManager
    private let historyStore: HistoryStore

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

    // MARK: - State

    private var isRecording = false

    // MARK: - Callbacks

    /// Called on the main thread when a transcription result is ready.
    public var onTranscriptionReady: ((TranscriptionResult) -> Void)?

    /// Called on the main thread when any pipeline error occurs.
    public var onError: ((Error) -> Void)?

    // MARK: - Init

    public init(
        audioCapture: AudioCaptureService = AudioCaptureService(),
        whisper: WhisperBridge = .shared,
        injector: TextInjector = TextInjector(),
        permissions: PermissionsManager = PermissionsManager(),
        historyStore: HistoryStore = HistoryStore()
    ) {
        self.audioCapture = audioCapture
        self.whisper = whisper
        self.injector = injector
        self.permissions = permissions
        self.historyStore = historyStore
    }

    // MARK: - Public API

    /// Begin audio capture. Call when the hotkey is pressed.
    /// - Throws: `PipelineError.alreadyRecording` if already active.
    public func startRecording() {
        guard !isRecording else {
            logger.warning("startRecording called while already recording — ignored.")
            return
        }

        do {
            try audioCapture.startCapture()
            isRecording = true
            logger.info("Recording started.")
        } catch {
            logger.error("Audio capture failed to start: \(error.localizedDescription)")
            DispatchQueue.main.async { [weak self] in
                self?.onError?(PipelineError.captureError(error))
            }
        }
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
            return nil
        }

        // Run transcription.
        flog.log(.info, "Starting Whisper transcription (\(pcmSamples.count) samples)...")
        let result: TranscriptionResult
        do {
            result = try await whisper.transcribe(pcm: pcmSamples, languageHint: languageHint)
            flog.log(.info, "Whisper returned: \"\(result.text)\"")
        } catch {
            flog.log(.error, "Whisper error: \(error.localizedDescription)")
            logger.error("Transcription error: \(error.localizedDescription)")
            await MainActor.run { onError?(PipelineError.transcriptionError(error)) }
            return nil
        }

        logger.info("Transcription complete: \"\(result.text)\" [\(result.language), \(result.durationMs)ms]")

        guard !result.text.isEmpty else {
            logger.info("Empty transcription result; nothing to inject.")
            return result
        }

        // Read the frontmost application context and resolve tone style.
        let injectionContext = await MainActor.run { contextService.currentContext() }
        var profile = cleanupProfile
        // If the profile has not been manually configured with a non-default tone,
        // auto-select tone from the active app's bundle ID.
        if profile.toneStyle == .casual && !profile.rawMode {
            profile = CleanupProfile(
                removeFillers: profile.removeFillers,
                addPunctuation: profile.addPunctuation,
                toneStyle: contextService.suggestedToneStyle(for: injectionContext.activeAppBundleID),
                rawMode: profile.rawMode
            )
        }

        // LLM cleanup step — never blocks injection on failure.
        let textToInject: String
        do {
            textToInject = try await llmProvider.cleanup(
                rawTranscript: result.text,
                context: injectionContext,
                profile: profile
            )
            if textToInject != result.text {
                logger.info("LLM cleanup applied. Original: \"\(result.text)\" → Cleaned: \"\(textToInject)\"")
            }
        } catch {
            logger.error("LLM cleanup threw an error: \(error.localizedDescription) — injecting raw transcript.")
            textToInject = result.text
        }

        // Inject text into focused window.
        await injector.inject(textToInject)

        // Persist to history.
        let entry = HistoryEntry.from(
            result: result,
            cleanedText: textToInject,
            appBundleID: injectionContext.activeAppBundleID
        )
        do {
            try await historyStore.insert(entry)
        } catch {
            logger.error("Failed to persist history entry: \(error.localizedDescription)")
            // Non-fatal — transcription was already injected successfully.
        }

        await MainActor.run { onTranscriptionReady?(result) }

        return result
    }
}
