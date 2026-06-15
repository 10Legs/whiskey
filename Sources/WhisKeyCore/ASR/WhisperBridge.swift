import CWhisper
import Foundation

/// Errors thrown by the WhisperBridge actor.
public enum WhisperError: Error, LocalizedError {
    case modelNotFound(URL)
    case initializationFailed
    case transcriptionFailed
    case emptyAudio
    case timeout

    public var errorDescription: String? {
        switch self {
        case .modelNotFound(let url):
            return "Whisper model not found at: \(url.path)"
        case .initializationFailed:
            return "Failed to initialize whisper context (model may be corrupt or incompatible)."
        case .transcriptionFailed:
            return "Transcription returned a non-zero error code."
        case .emptyAudio:
            return "Audio buffer is empty; nothing to transcribe."
        case .timeout:
            return "Transcription timed out after 30 seconds."
        }
    }
}

/// Thread-safe actor that manages a single whisper.cpp inference context.
///
/// The model is loaded lazily on first use from:
///   ~/Library/Application Support/WhisKey/Models/ggml-tiny.en.bin
///
/// Use `WhisperBridge.shared` for the global instance, or instantiate directly
/// when multiple models are needed.
public actor WhisperBridge {

    // MARK: - Shared instance

    public static let shared = WhisperBridge()

    // MARK: - Configuration

    /// File name of the active model binary. Mutable so `resetContext` can swap models at runtime.
    private var modelFileName: String

    /// Override the model directory (defaults to Application Support).
    private let modelDirectoryURL: URL

    /// Number of CPU threads passed to whisper_full.
    private let nThreads: Int

    // MARK: - State

    nonisolated(unsafe) private var context: OpaquePointer?

    // MARK: - Init

    public init(
        modelFileName: String = "ggml-tiny.en.bin",
        modelDirectoryURL: URL? = nil,
        nThreads: Int = 4
    ) {
        self.modelFileName = modelFileName
        self.nThreads = nThreads
        if let dir = modelDirectoryURL {
            self.modelDirectoryURL = dir
        } else {
            let appSupport = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first! // swiftlint:disable:this force_unwrapping
            self.modelDirectoryURL = appSupport
                .appendingPathComponent("WhisKey")
                .appendingPathComponent("Models")
        }
    }

    deinit {
        if let ctx = context {
            whisper_bridge_free(ctx)
        }
    }

    // MARK: - Public API

    /// Replace the active model. Frees the current whisper.cpp context so the
    /// next `transcribe` call loads from the new file.
    public func resetContext(newModelFileName: String) {
        if let ctx = context {
            whisper_bridge_free(ctx)
            context = nil
        }
        modelFileName = newModelFileName
    }

    /// Transcribe raw PCM audio (16 kHz, mono, Float32).
    ///
    /// - Parameters:
    ///   - pcm: Array of Float32 samples at 16 kHz.
    ///   - languageHint: BCP-47 language code to force, or nil for auto-detect.
    ///   - initialPrompt: Comma-separated vocabulary terms to bias Whisper beam
    ///     search. Mapped to `whisper_full_params.initial_prompt`. Pass nil or
    ///     empty string to disable. Example: "SwiftUI, Xcode, WhisKey".
    /// - Returns: A `TranscriptionResult` with the transcribed text and metadata.
    public func transcribe(
        pcm: [Float],
        languageHint: String? = nil,
        initialPrompt: String? = nil
    ) async throws -> TranscriptionResult {
        guard !pcm.isEmpty else { throw WhisperError.emptyAudio }

        let ctx = try loadContextIfNeeded()
        // Capture actor-isolated state before escaping to nonisolated context.
        let threadCount = nThreads
        // OpaquePointer is not Sendable; erase to UInt (Sendable) for the task boundary.
        let ctxBits = UInt(bitPattern: ctx)
        // Normalise prompt: treat empty string same as nil.
        let prompt: String? = initialPrompt.flatMap { $0.isEmpty ? nil : $0 }

        let result: TranscriptionResult = try await withThrowingTaskGroup(of: TranscriptionResult.self) { group in
            // Inference task -- runs whisper.cpp off the actor via a continuation.
            group.addTask { @Sendable in
                try await withCheckedThrowingContinuation { continuation in
                    DispatchQueue.global(qos: .userInitiated).async {
                        guard let ctxPtr = OpaquePointer(bitPattern: ctxBits) else {
                            continuation.resume(throwing: WhisperError.transcriptionFailed)
                            return
                        }
                        let bridgeResult = pcm.withUnsafeBufferPointer { buf in
                            whisper_bridge_transcribe(
                                ctxPtr,
                                buf.baseAddress,
                                Int32(buf.count),
                                languageHint,
                                Int32(threadCount),
                                prompt
                            )
                        }

                        let text = bridgeResult.text.flatMap { String(cString: $0) } ?? ""
                        let lang = bridgeResult.language.flatMap { String(cString: $0) } ?? "unknown"
                        let duration = bridgeResult.duration_ms

                        var mutableResult = bridgeResult
                        whisper_bridge_result_free(&mutableResult)

                        continuation.resume(returning: TranscriptionResult(
                            text: text,
                            durationMs: duration,
                            language: lang
                        ))
                    }
                }
            }

            // Timeout task -- fires after 30 seconds.
            group.addTask {
                try await Task.sleep(nanoseconds: 30_000_000_000)
                throw WhisperError.timeout
            }

            // First task to finish wins; cancel the other.
            guard let first = try await group.next() else {
                throw WhisperError.transcriptionFailed
            }
            group.cancelAll()
            return first
        }

        return result
    }

    /// Returns true if the loaded model supports multiple languages.
    public func isMultilingual() throws -> Bool {
        let ctx = try loadContextIfNeeded()
        return whisper_bridge_is_multilingual(ctx)
    }

    /// Eagerly load (mmap + context alloc) the Whisper model so the first
    /// dictation does not block on lazy initialization. Mirrors the LLM eager
    /// warmup. Failures are logged but never thrown — warmup is best-effort.
    public func warmUpWhisper() {
        do {
            let ctx = try loadContextIfNeeded()
            // Run a dummy inference so Metal compute pipelines are compiled now,
            // at startup, rather than on the first real dictation.
            let warmPCM = [Float](repeating: 0.0, count: 8_000) // 0.5s @16kHz
            _ = warmPCM.withUnsafeBufferPointer {
                whisper_bridge_transcribe(ctx, $0.baseAddress, Int32($0.count), "en", Int32(nThreads), nil)
            }
        } catch {
            FileLogger.shared.log(.warn, "WhisperBridge: warmUpWhisper failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    private func loadContextIfNeeded() throws -> OpaquePointer {
        if let existing = context { return existing }

        let modelURL = modelDirectoryURL.appendingPathComponent(modelFileName)
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw WhisperError.modelNotFound(modelURL)
        }

        guard let ctx = whisper_bridge_init(modelURL.path) else {
            throw WhisperError.initializationFailed
        }

        context = ctx
        return ctx
    }
}
