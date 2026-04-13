import Foundation

/// The output of a successful transcription pass.
public struct TranscriptionResult: Sendable {
    /// The transcribed text with leading/trailing whitespace trimmed.
    public let text: String

    /// Total audio duration that was processed, in milliseconds.
    public let durationMs: Int64

    /// BCP-47 language code as detected or forced (e.g. "en", "es").
    public let language: String

    /// Wall-clock timestamp of when the transcription completed.
    public let timestamp: Date

    public init(text: String, durationMs: Int64, language: String, timestamp: Date = .now) {
        self.text = text.trimmingCharacters(in: .whitespaces)
        self.durationMs = durationMs
        self.language = language
        self.timestamp = timestamp
    }
}
