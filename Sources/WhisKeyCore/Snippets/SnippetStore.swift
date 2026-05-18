import Foundation
import os.log

private let logger = Logger(subsystem: "com.whiskey.app", category: "SnippetStore")

// MARK: - SnippetStore

/// Actor-isolated persistent store for voice-expansion snippets.
///
/// Snippets are serialised as JSON to
/// `~/Library/Application Support/WhisKey/snippets.json`.
/// All mutations hold the complete array in memory and write atomically —
/// the in-memory cache is the source of truth; the file is the durable copy.
///
/// Error model: every throwing method documents the failure conditions.
/// Callers that cannot recover (e.g. UI) should surface the `localizedDescription`
/// to the user via the existing error-banner surface in the popover.
public actor SnippetStore {

    // MARK: - Singleton

    /// Shared store. Initialised once; all access is actor-isolated.
    public static let shared = SnippetStore()

    // MARK: - Storage

    /// In-memory cache. `nil` means the store has not yet been loaded from disk.
    private var cachedSnippets: [Snippet]?

    // MARK: - File Layout

    /// `~/Library/Application Support/WhisKey/snippets.json`
    private static var storeURL: URL {
        get throws {
            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let dir = appSupport.appendingPathComponent("WhisKey", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir.appendingPathComponent("snippets.json")
        }
    }

    // MARK: - JSON Envelope

    /// Top-level container matching the v1 JSON schema documented in S3-C3.
    private struct SnippetsFile: Codable {
        var version: Int
        var exportedAt: Date?
        var snippets: [Snippet]
    }

    private static let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return enc
    }()

    private static let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()

    // MARK: - Init

    private init() {}

    // MARK: - Public Read API

    /// Returns all snippets, loading from disk on first call.
    ///
    /// If the file is absent the store is treated as empty (not an error).
    /// If the file is present but unreadable, a `SnippetStoreError.loadFailed`
    /// is thrown; the pipeline treats the store as empty until the user resets it.
    public func allSnippets() async -> [Snippet] {
        if let cached = cachedSnippets { return cached }
        do {
            return try await loadAll()
        } catch {
            logger.error("SnippetStore: failed to load snippets — treating as empty. \(error.localizedDescription)")
            return []
        }
    }

    /// Loads snippets from disk, populates the in-memory cache, and returns the array.
    ///
    /// - Throws: `SnippetStoreError.loadFailed` if the file exists but cannot be parsed.
    @discardableResult
    public func loadAll() async throws -> [Snippet] {
        let url: URL
        do {
            url = try Self.storeURL
        } catch {
            throw SnippetStoreError.loadFailed(error)
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            cachedSnippets = []
            return []
        }

        do {
            let data = try Data(contentsOf: url)
            let file = try Self.decoder.decode(SnippetsFile.self, from: data)
            cachedSnippets = file.snippets
            logger.info("SnippetStore: loaded \(file.snippets.count) snippet(s) from disk.")
            return file.snippets
        } catch {
            throw SnippetStoreError.loadFailed(error)
        }
    }

    // MARK: - Public Write API

    /// Adds a new snippet or replaces an existing one matched by `id`.
    ///
    /// - Throws: `SnippetStoreError.invalidTrigger` when the trigger phrase
    ///   contains fewer than 3 whitespace-delimited words.
    /// - Throws: `SnippetStoreError.saveFailed` on I/O failure.
    public func save(_ snippet: Snippet) async throws {
        let wordCount = snippet.triggerPhrase
            .split(whereSeparator: \.isWhitespace)
            .count
        guard wordCount >= 3 else {
            throw SnippetStoreError.invalidTrigger(
                "Trigger phrase must contain at least 3 words to reduce accidental matches. " +
                "Got \(wordCount) word(s) in \"\(snippet.triggerPhrase)\"."
            )
        }

        if cachedSnippets == nil {
            try await loadAll()
        }
        var snippets = cachedSnippets ?? []
        var updated = snippet
        updated.updatedAt = Date()

        if let index = snippets.firstIndex(where: { $0.id == snippet.id }) {
            snippets[index] = updated
        } else {
            snippets.append(updated)
        }

        try await persist(snippets)
    }

    /// Deletes the snippet with the given `id`. No-op if the id is not found.
    ///
    /// - Throws: `SnippetStoreError.saveFailed` on I/O failure.
    public func delete(id: UUID) async throws {
        if cachedSnippets == nil {
            try await loadAll()
        }
        var snippets = cachedSnippets ?? []
        snippets.removeAll { $0.id == id }
        try await persist(snippets)
    }

    /// Increments `useCount` for the snippet with the given `id` and persists.
    ///
    /// Called by the pipeline after a confirmed successful injection.
    /// Silently no-ops if the id is not found or persistence fails (non-critical counter).
    public func incrementUseCount(id: UUID) async {
        guard var snippets = cachedSnippets else { return }
        guard let index = snippets.firstIndex(where: { $0.id == id }) else { return }
        snippets[index].useCount += 1
        snippets[index].updatedAt = Date()
        do {
            try await persist(snippets)
        } catch {
            logger.warning("SnippetStore: failed to persist useCount increment — \(error.localizedDescription)")
        }
    }

    /// Replaces all snippets with the given array and persists atomically.
    ///
    /// - Throws: `SnippetStoreError.saveFailed` on I/O failure.
    public func replaceAll(_ snippets: [Snippet]) async throws {
        try await persist(snippets)
    }

    // MARK: - Export / Import

    /// Serialises all snippets to JSON data suitable for writing to a user-chosen file.
    ///
    /// The export envelope includes the `exportedAt` timestamp per the v1 schema.
    /// - Throws: encoding error or `SnippetStoreError.saveFailed`.
    public func exportJSON() async throws -> Data {
        let snippets = await allSnippets()
        let file = SnippetsFile(version: 1, exportedAt: Date(), snippets: snippets)
        return try Self.encoder.encode(file)
    }

    /// Imports snippets from JSON data.
    ///
    /// - Parameters:
    ///   - data: Raw JSON data from a user-selected file.
    ///   - mode: `.merge` adds new snippets, skipping those whose trigger phrase
    ///     already exists (case-insensitive). `.replace` overwrites the entire store.
    /// - Returns: An `ImportResult` describing what changed.
    /// - Throws: `SnippetStoreError.importFailed` for schema / version / parse errors.
    public func importJSON(_ data: Data, mode: ImportMode) async throws -> ImportResult {
        let file: SnippetsFile
        do {
            file = try Self.decoder.decode(SnippetsFile.self, from: data)
        } catch {
            throw SnippetStoreError.importFailed("The file is not a valid WhisKey snippets export. (\(error.localizedDescription))")
        }

        guard file.version == 1 else {
            throw SnippetStoreError.importFailed(
                "This file was exported from a newer version of WhisKey (schema v\(file.version)). " +
                "Please update the app."
            )
        }

        guard !file.snippets.isEmpty else {
            throw SnippetStoreError.importFailed("The import file contains no valid snippets.")
        }

        switch mode {
        case .replace:
            // Generate fresh UUIDs for all imported snippets to avoid ID collisions.
            let fresh = file.snippets.map { src -> Snippet in
                var copy = src
                _ = copy // suppress unused warning; mutation below is the point
                return Snippet(triggerPhrase: src.triggerPhrase, expansionText: src.expansionText, isEnabled: src.isEnabled)
            }
            try await persist(fresh)
            return ImportResult(added: fresh.count, skipped: 0, conflicts: [])

        case .merge:
            var existing = await allSnippets()
            let existingTriggers = Set(existing.map { $0.triggerPhrase.lowercased() })
            var added = 0
            var conflicts: [String] = []

            for src in file.snippets {
                let lower = src.triggerPhrase.lowercased()
                if existingTriggers.contains(lower) {
                    conflicts.append(src.triggerPhrase)
                } else {
                    // Fresh UUID to prevent ID collisions with the existing store.
                    let fresh = Snippet(
                        triggerPhrase: src.triggerPhrase,
                        expansionText: src.expansionText,
                        isEnabled: src.isEnabled
                    )
                    existing.append(fresh)
                    added += 1
                }
            }

            try await persist(existing)
            return ImportResult(added: added, skipped: conflicts.count, conflicts: conflicts)
        }
    }

    // MARK: - Conflict Detection

    /// Returns pairs of snippet IDs whose trigger phrases overlap (one is a substring of the other).
    ///
    /// Used by the Settings UI to show per-row conflict badges at save time.
    public func overlappingTriggers() async -> [(UUID, UUID)] {
        let snippets = await allSnippets()
        var pairs: [(UUID, UUID)] = []
        for outerIdx in snippets.indices {
            for innerIdx in snippets.indices where innerIdx > outerIdx {
                let outerTrigger = snippets[outerIdx].triggerPhrase.lowercased()
                let innerTrigger = snippets[innerIdx].triggerPhrase.lowercased()
                if outerTrigger.contains(innerTrigger) || innerTrigger.contains(outerTrigger) {
                    pairs.append((snippets[outerIdx].id, snippets[innerIdx].id))
                }
            }
        }
        return pairs
    }

    // MARK: - Private Persistence

    /// Writes the canonical snippets array to disk atomically via a temp file.
    ///
    /// Strategy: encode → write to `snippets.json.tmp` → `FileManager.replaceItem`
    /// (atomic rename). Prevents partial writes from corrupting the live store.
    private func persist(_ snippets: [Snippet]) async throws {
        let url: URL
        do {
            url = try Self.storeURL
        } catch {
            throw SnippetStoreError.saveFailed(error)
        }

        let file = SnippetsFile(version: 1, exportedAt: nil, snippets: snippets)
        let data: Data
        do {
            data = try Self.encoder.encode(file)
        } catch {
            throw SnippetStoreError.saveFailed(error)
        }

        let tmpURL = url.deletingLastPathComponent()
            .appendingPathComponent("snippets.json.tmp")

        do {
            try data.write(to: tmpURL, options: .atomic)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmpURL)
        } catch {
            // Best-effort cleanup of temp file.
            try? FileManager.default.removeItem(at: tmpURL)
            throw SnippetStoreError.saveFailed(error)
        }

        cachedSnippets = snippets
        logger.info("SnippetStore: persisted \(snippets.count) snippet(s).")
    }

    // MARK: - Reset

    /// Deletes the snippets file from disk and clears the in-memory cache.
    ///
    /// Presented to the user as a recovery path when the file is unreadable.
    /// - Throws: file-system error if the file cannot be removed.
    public func reset() async throws {
        let url = try Self.storeURL
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        cachedSnippets = []
        logger.warning("SnippetStore: store reset — all snippets deleted.")
    }
}

// MARK: - Import Mode

public extension SnippetStore {
    /// Controls how imported snippets are merged with the live store.
    enum ImportMode: Sendable {
        /// Add imported snippets; skip those whose trigger phrase already exists.
        case merge
        /// Replace the entire store with the imported snippets.
        case replace
    }

    /// Summary of a completed import operation.
    struct ImportResult: Sendable {
        /// Number of snippets successfully added.
        public let added: Int
        /// Number of snippets skipped due to duplicate trigger phrases.
        public let skipped: Int
        /// Trigger phrases that were skipped.
        public let conflicts: [String]
    }
}

// MARK: - Errors

/// Errors produced by `SnippetStore`.
public enum SnippetStoreError: Error, LocalizedError {
    /// The snippets file exists but could not be parsed or read.
    case loadFailed(Error)
    /// A write or atomic-rename operation failed.
    case saveFailed(Error)
    /// The trigger phrase failed the minimum word-count validation.
    case invalidTrigger(String)
    /// Import data was malformed, wrong schema version, or empty.
    case importFailed(String)

    public var errorDescription: String? {
        switch self {
        case .loadFailed(let err):
            return "Snippets could not be loaded: \(err.localizedDescription)"
        case .saveFailed(let err):
            return "Snippets could not be saved: \(err.localizedDescription)"
        case .invalidTrigger(let reason):
            return reason
        case .importFailed(let reason):
            return "Could not import: \(reason)"
        }
    }
}
