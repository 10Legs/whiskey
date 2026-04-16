import Foundation
import GRDB
import os.log

private let logger = Logger(subsystem: "com.whiskey.app", category: "SettingsManager")

/// Persisted settings backed by SQLite key-value table.
///
/// `@Observable` so SwiftUI views react to changes. Marked `@MainActor`
/// because SwiftUI observation requires main-thread property access.
/// Database writes are synchronous through GRDB's `DatabasePool.write`.
@Observable
@MainActor
public final class SettingsManager: @unchecked Sendable {

    private let db: AppDatabase

    /// In-memory cache of all settings, loaded on init.
    private var cache: [String: String] = [:]

    // MARK: - Init

    public init(db: AppDatabase = .shared) {
        self.db = db
        loadCache()
    }

    private func loadCache() {
        do {
            let rows = try db.pool.read { db in
                try Row.fetchAll(db, sql: "SELECT key, value FROM settings")
            }
            for row in rows {
                let key: String = row["key"]
                let value: String = row["value"]
                cache[key] = value
            }
            logger.info("Settings loaded: \(self.cache.count) keys")
        } catch {
            logger.error("Failed to load settings: \(error.localizedDescription)")
        }
    }

    // MARK: - Generic Get / Set

    /// Read a JSON-decoded value for a settings key.
    public func get<T: Decodable>(_ key: SettingsKey, default defaultValue: T) -> T {
        guard let raw = cache[key.rawValue],
              let data = raw.data(using: .utf8) else {
            return defaultValue
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            return defaultValue
        }
    }

    /// Write a JSON-encoded value for a settings key.
    public func set<T: Encodable>(_ key: SettingsKey, value: T) {
        do {
            let data = try JSONEncoder().encode(value)
            let json = String(data: data, encoding: .utf8) ?? ""
            cache[key.rawValue] = json

            try db.pool.write { db in
                try db.execute(
                    sql: """
                    INSERT INTO settings (key, value) VALUES (?, ?)
                    ON CONFLICT(key) DO UPDATE SET value = excluded.value
                    """,
                    arguments: [key.rawValue, json]
                )
            }
        } catch {
            logger.error("Failed to write setting \(key.rawValue): \(error.localizedDescription)")
        }
    }

    // MARK: - Typed Accessors

    public var whisperModel: String {
        get { get(.whisperModel, default: "ggml-tiny.en") }
        set { set(.whisperModel, value: newValue) }
    }

    public var languageHint: String? {
        get { get(.languageHint, default: nil as String?) }
        set { set(.languageHint, value: newValue) }
    }

    public var llmProviderName: String {
        get { get(.llmProvider, default: "llamacpp") }
        set { set(.llmProvider, value: newValue) }
    }

    public var toneStyle: ToneStyle {
        get {
            let raw: String = get(.toneStyle, default: ToneStyle.casual.rawValue)
            return ToneStyle(rawValue: raw) ?? .casual
        }
        set { set(.toneStyle, value: newValue.rawValue) }
    }

    public var removeFillers: Bool {
        get { get(.removeFillers, default: true) }
        set { set(.removeFillers, value: newValue) }
    }

    public var addPunctuation: Bool {
        get { get(.addPunctuation, default: true) }
        set { set(.addPunctuation, value: newValue) }
    }

    public var rawMode: Bool {
        get { get(.rawMode, default: false) }
        set { set(.rawMode, value: newValue) }
    }

    public var outputMode: OutputMode {
        get {
            let raw: String = get(.outputMode, default: OutputMode.activeWindow.rawValue)
            return OutputMode(rawValue: raw) ?? .activeWindow
        }
        set { set(.outputMode, value: newValue.rawValue) }
    }

    /// Builds a `CleanupProfile` from current settings.
    public var cleanupProfile: CleanupProfile {
        CleanupProfile(
            removeFillers: removeFillers,
            addPunctuation: addPunctuation,
            toneStyle: toneStyle,
            rawMode: rawMode
        )
    }
}
