import Foundation

/// Orchestrates the full voice → text pipeline:
/// Audio capture → Whisper ASR → Context enrichment → LLM cleanup → Text injection
public final class TranscriptionPipeline {
    // TODO: inject dependencies via initializer once components are implemented
    // - AudioCapturePipeline
    // - WhisperEngine
    // - LLMCleanupEngine
    // - TextInjector
    // - ContextReader

    public init() {}

    /// Begin recording. Call when hotkey is pressed.
    public func startRecording() {
        // TODO
    }

    /// Stop recording, run transcription + cleanup, inject result.
    public func stopAndTranscribe() async throws {
        // TODO
    }
}
