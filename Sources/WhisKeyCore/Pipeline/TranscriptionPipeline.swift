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

    // MARK: - Configuration

    /// BCP-47 language hint passed to Whisper. nil = auto-detect.
    public var languageHint: String? = nil

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
        permissions: PermissionsManager = PermissionsManager()
    ) {
        self.audioCapture = audioCapture
        self.whisper = whisper
        self.injector = injector
        self.permissions = permissions
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
        logger.info("Recording stopped. Captured \(pcmSamples.count) samples.")

        guard !pcmSamples.isEmpty else {
            logger.warning("No audio samples captured; skipping transcription.")
            return nil
        }

        // Run transcription.
        let result: TranscriptionResult
        do {
            result = try await whisper.transcribe(pcm: pcmSamples, languageHint: languageHint)
        } catch {
            logger.error("Transcription error: \(error.localizedDescription)")
            await MainActor.run { onError?(PipelineError.transcriptionError(error)) }
            return nil
        }

        logger.info("Transcription complete: \"\(result.text)\" [\(result.language), \(result.durationMs)ms]")

        guard !result.text.isEmpty else {
            logger.info("Empty transcription result; nothing to inject.")
            return result
        }

        // Inject text into focused window.
        await injector.inject(result.text)

        await MainActor.run { onTranscriptionReady?(result) }

        return result
    }
}
