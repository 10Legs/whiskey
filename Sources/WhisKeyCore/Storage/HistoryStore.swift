import Foundation
import GRDB
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

    /// Insert a new history entry.
    public func insert(_ entry: HistoryEntry) throws {
        try db.pool.write { db in
            try entry.insert(db)
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

    /// Fetch a single entry by ID.
    public func fetch(id: String) throws -> HistoryEntry? {
        try db.pool.read { db in
            try HistoryEntry.fetchOne(db, key: id)
        }
    }

    // MARK: - Delete

    /// Delete a single entry by ID.
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
