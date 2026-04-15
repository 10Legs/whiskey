import Foundation
import CWhisper

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

    /// File name of the default model binary.
    private let modelFileName: String

    /// Override the model directory (defaults to Application Support).
    private let modelDirectoryURL: URL

    /// Number of CPU threads passed to whisper_full.
    private let nThreads: Int

    // MARK: - State

    private var context: OpaquePointer?

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
                .first!
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

    /// Transcribe raw PCM audio (16 kHz, mono, Float32).
    ///
    /// - Parameters:
    ///   - pcm: Array of Float32 samples at 16 kHz.
    ///   - languageHint: BCP-47 language code to force, or nil for auto-detect.
    /// - Returns: A `TranscriptionResult` with the transcribed text and metadata.
    public func transcribe(pcm: [Float], languageHint: String? = nil) async throws -> TranscriptionResult {
        guard !pcm.isEmpty else { throw WhisperError.emptyAudio }

        let ctx = try loadContextIfNeeded()

        let result: TranscriptionResult = try await withThrowingTaskGroup(of: TranscriptionResult.self) { group in
            // Inference task — runs whisper.cpp on a background thread.
            group.addTask(priority: .userInitiated) {
                try await withCheckedThrowingContinuation { continuation in
                    Task.detached(priority: .userInitiated) {
                        let bridgeResult = pcm.withUnsafeBufferPointer { buf in
                            whisper_bridge_transcribe(
                                ctx,
                                buf.baseAddress,
                                Int32(buf.count),
                                languageHint,
                                Int32(self.nThreads)
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

            // Timeout task — fires after 30 seconds.
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
