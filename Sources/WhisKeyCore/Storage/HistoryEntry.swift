import Foundation
import GRDB

/// A persisted transcription record.
public struct HistoryEntry: Codable, Sendable, Identifiable {
    public var id: String
    /// LLM-cleaned (or raw-passthrough) text, depending on `cleaned`.
    public var text: String
    /// Raw Whisper output before LLM cleanup, if cleanup ran.
    public var rawText: String?
    public var language: String
    public var durationMs: Int64
    public var timestamp: TimeInterval
    public var appBundleID: String?
    /// `true` when the LLM cleanup step ran on this entry; `false` for raw passthrough.
    /// Added in schema migration v2.
    public var cleaned: Bool
    /// Denormalized character count of `text`. Cheap for aggregation/sorting without scanning.
    /// Added in schema migration v2.
    public var charCount: Int

    public init(
        id: String = UUID().uuidString,
        text: String,
        rawText: String? = nil,
        language: String,
        durationMs: Int64,
        timestamp: TimeInterval = Date.now.timeIntervalSince1970,
        appBundleID: String? = nil,
        cleaned: Bool = true,
        charCount: Int? = nil
    ) {
        self.id = id
        self.text = text
        self.rawText = rawText
        self.language = language
        self.durationMs = durationMs
        self.timestamp = timestamp
        self.appBundleID = appBundleID
        self.cleaned = cleaned
        self.charCount = charCount ?? text.count
    }
}

// MARK: - GRDB Conformances

extension HistoryEntry: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "history"
}

// MARK: - Convenience

extension HistoryEntry {
    /// Creates a `HistoryEntry` from a pipeline `TranscriptionResult`.
    public static func from(
        result: TranscriptionResult,
        cleanedText: String,
        appBundleID: String?,
        cleaned: Bool = true
    ) -> HistoryEntry {
        HistoryEntry(
            text: cleanedText,
            rawText: result.text,
            language: result.language,
            durationMs: result.durationMs,
            timestamp: result.timestamp.timeIntervalSince1970,
            appBundleID: appBundleID,
            cleaned: cleaned,
            charCount: cleanedText.count
        )
    }
}
