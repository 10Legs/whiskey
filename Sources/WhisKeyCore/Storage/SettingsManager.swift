import Foundation
import GRDBEncrypted
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

    public var notificationsEnabled: Bool {
        get { get(.notificationsEnabled, default: true) }
        set { set(.notificationsEnabled, value: newValue) }
    }

    /// When `false`, the LLM cleanup step is skipped entirely and the raw Whisper
    /// transcript is injected verbatim. Defaults to `false`.
    public var llmEnabled: Bool {
        get { get(.llmEnabled, default: false) }
        set { set(.llmEnabled, value: newValue) }
    }

    /// Currently selected Whisper model ID (e.g. "ggml-base.en").
    public var activeModelID: String? {
        get { get(.activeModelID, default: nil as String?) }
        set { set(.activeModelID, value: newValue) }
    }

    /// Maximum number of history entries to retain.
    /// After every insert, `HistoryStore` trims entries beyond this count (oldest first).
    /// Clamped to the range 50–10000. Default: 500.
    public var historyRetentionMax: Int {
        get {
            let raw: Int = get(.historyRetentionMax, default: 500)
            return max(50, min(10_000, raw))
        }
        set { set(.historyRetentionMax, value: max(50, min(10_000, newValue))) }
    }

    /// When `false`, the energy-based silence trimmer is not applied to captured PCM. Defaults to `true`.
    public var silenceTrimEnabled: Bool {
        get { get(.silenceTrimEnabled, default: true) }
        set { set(.silenceTrimEnabled, value: newValue) }
    }

    /// When `false`, the post-Whisper filler-word regex scrubber is not applied. Defaults to `true`.
    public var fillerScrubberEnabled: Bool {
        get { get(.fillerScrubberEnabled, default: true) }
        set { set(.fillerScrubberEnabled, value: newValue) }
    }

    /// Per-application transcription profiles stored as a JSON array.
    /// Defaults to a single wildcard profile when empty.
    public var appProfiles: [AppProfile] {
        get {
            let profiles: [AppProfile] = get(.appProfiles, default: [])
            return profiles.isEmpty ? [AppProfile.makeDefault()] : profiles
        }
        set { set(.appProfiles, value: newValue) }
    }

    /// When `false`, only push-to-talk mode is active; hands-free double-tap is disabled. (S3-T4)
    public var handsFreeEnabled: Bool {
        get { get(.handsFreeEnabled, default: true) }
        set { set(.handsFreeEnabled, value: newValue) }
    }

    /// When `false`, the floating waveform HUD is hidden. Defaults to `true`.
    public var hudEnabled: Bool {
        get { get(.hudEnabled, default: true) }
        set { set(.hudEnabled, value: newValue) }
    }

    /// How long the live-preview caption strip lingers after the final transcript
    /// is injected. Defaults to `.linger(seconds: 2)` (UX-approved P2 default).
    public var previewLingerMode: PreviewLingerMode {
        get { get(.previewLingerMode, default: PreviewLingerMode.linger(seconds: 2)) }
        set { set(.previewLingerMode, value: newValue) }
    }

    /// Double-tap disambiguation window in milliseconds. Default: 300. Valid range: 200-500. (S3-T4)
    public var disambiguationWindowMs: Double {
        get {
            let raw: Double = get(.disambiguationWindowMs, default: 300.0)
            return max(200.0, min(500.0, raw))
        }
        set { set(.disambiguationWindowMs, value: max(200.0, min(500.0, newValue))) }
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
