import Foundation
import GRDBEncrypted
import os.log

private let logger = Logger(subsystem: "com.whiskey.app", category: "HistoryStore")

/// Actor-isolated persistence layer for transcription history.
///
/// All mutations are serialized through actor isolation. The underlying
/// `DatabasePool` allows concurrent reads from SwiftUI observation.
public actor HistoryStore {

    private let db: AppDatabase

    public init(db: AppDatabase = .shared) {
        self.db = db
    }

    // MARK: - Write

    /// Insert a new history entry and trim to `maxEntries`.
    ///
    /// The insert and retention trim run in a single write transaction to avoid
    /// a race window where two rapid inserts both read the same pre-trim count.
    ///
    /// - Parameters:
    ///   - entry: The entry to persist.
    ///   - maxEntries: Retention cap — entries beyond this count (oldest first) are deleted.
    ///                 Read from `SettingsManager.historyRetentionMax` by the caller.
    ///                 Valid range 50–10000; defaults to 500.
    public func insert(_ entry: HistoryEntry, maxEntries: Int = 500) throws {
        try db.pool.write { db in
            try entry.insert(db)
            // Trim: keep only the most recent `maxEntries` rows by timestamp.
            // Runs inside the same transaction as insert.
            try db.execute(
                sql: """
                DELETE FROM history
                WHERE id NOT IN (
                    SELECT id FROM history ORDER BY timestamp DESC LIMIT ?
                )
                """,
                arguments: [maxEntries]
            )
        }
        logger.info("Saved history entry \(entry.id)")
    }

    // MARK: - Read

    /// Fetch the most recent entries, ordered by timestamp descending.
    public func fetchRecent(limit: Int = 50) throws -> [HistoryEntry] {
        try db.pool.read { db in
            try HistoryEntry
                .order(Column("timestamp").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Fetch a page of entries for the history popover.
    ///
    /// - Parameters:
    ///   - limit: Page size (typically 20).
    ///   - offset: Row offset from the most-recent entry.
    public func fetchPage(limit: Int, offset: Int) throws -> [HistoryEntry] {
        try db.pool.read { db in
            try HistoryEntry
                .order(Column("timestamp").desc)
                .limit(limit, offset: offset)
                .fetchAll(db)
        }
    }

    /// Total number of history entries in the store.
    public func count() throws -> Int {
        try db.pool.read { db in
            try HistoryEntry.fetchCount(db)
        }
    }

    /// Fetch a single entry by ID.
    public func fetch(id: String) throws -> HistoryEntry? {
        try db.pool.read { db in
            try HistoryEntry.fetchOne(db, key: id)
        }
    }

    // MARK: - Delete

    /// Delete a single entry by ID.
    @discardableResult
    public func delete(id: String) throws -> Bool {
        try db.pool.write { db in
            try HistoryEntry.deleteOne(db, key: id)
        }
    }

    /// Delete all history entries.
    public func deleteAll() throws {
        try db.pool.write { db in
            _ = try HistoryEntry.deleteAll(db)
        }
        logger.info("All history entries deleted.")
    }
}
