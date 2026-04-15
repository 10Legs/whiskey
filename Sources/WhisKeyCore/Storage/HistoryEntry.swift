import Foundation
import GRDB

/// A persisted transcription record.
public struct HistoryEntry: Codable, Sendable, Identifiable {
    public var id: String
    public var text: String
    public var rawText: String?
    public var language: String
    public var durationMs: Int64
    public var timestamp: TimeInterval
    public var appBundleID: String?

    public init(
        id: String = UUID().uuidString,
        text: String,
        rawText: String? = nil,
        language: String,
        durationMs: Int64,
        timestamp: TimeInterval = Date.now.timeIntervalSince1970,
        appBundleID: String? = nil
    ) {
        self.id = id
        self.text = text
        self.rawText = rawText
        self.language = language
        self.durationMs = durationMs
        self.timestamp = timestamp
        self.appBundleID = appBundleID
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
        appBundleID: String?
    ) -> HistoryEntry {
        HistoryEntry(
            text: cleanedText,
            rawText: result.text,
            language: result.language,
            durationMs: result.durationMs,
            timestamp: result.timestamp.timeIntervalSince1970,
            appBundleID: appBundleID
        )
    }
}
