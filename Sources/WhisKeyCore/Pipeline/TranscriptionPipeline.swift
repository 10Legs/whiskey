import AppKit
import ApplicationServices
import Combine
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

        // Snapshot the focused AX element NOW — before transcription latency causes focus to change.
        let capturedAXElement: AXUIElement? = await MainActor.run {
            guard AXIsProcessTrusted() else { return nil }
            let sysWide = AXUIElementCreateSystemWide()
            var ref: CFTypeRef?
            AXUIElementCopyAttributeValue(sysWide, kAXFocusedUIElementAttribute as CFString, &ref)
            return ref.map { $0 as! AXUIElement }  // swiftlint:disable:this force_cast
        }

        guard let result = await runTranscription(pcmSamples: pcmSamples) else { return nil }

        guard !result.text.isEmpty else {
            logger.info("Empty transcription result; nothing to inject.")
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
        }
        await MainActor.run { onTranscriptionReady?(result) }
    }
}
