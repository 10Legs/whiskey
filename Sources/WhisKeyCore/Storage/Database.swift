import Foundation
import GRDB
import os.log

private let logger = Logger(subsystem: "com.whiskey.app", category: "Database")

// MARK: - DatabaseError

/// Errors surfaced by `AppDatabase` startup and wipe operations.
public enum DatabaseError: Error, Sendable {
    /// Generic open/migrate failure.
    case openFailed(Error)
}

// MARK: - AppDatabase

/// Central database manager. Creates the SQLite file, runs migrations, and
/// vends a `DatabasePool` for use by `HistoryStore` and `SettingsManager`.
///
/// Uses plain SQLite (no encryption). The database is stored at
/// `~/Library/Application Support/WhisKey/whiskey.sqlite`.
///
/// If the pool fails to open (e.g., the file is a stale SQLCipher-encrypted
/// database from a previous build), the file and its WAL/SHM sidecars are
/// deleted and a fresh database is created automatically. This is safe because
/// there are no production users and dev data is not precious.
public final class AppDatabase: Sendable {

    /// The GRDB connection pool (WAL mode, concurrent readers, plain SQLite).
    public let pool: DatabasePool

    // MARK: - Singleton

    /// Shared instance pointing at the default Application Support path.
    public static let shared: AppDatabase = {
        do {
            let path = AppDatabase.defaultDatabasePath()
            return try AppDatabase(path: path)
        } catch {
            fatalError("AppDatabase failed to initialize: \(error)")
        }
    }()

    // MARK: - Init

    /// Creates (or opens) the plain SQLite database at `path`.
    ///
    /// If `DatabasePool` throws on open (likely a stale SQLCipher-encrypted file
    /// from a prior build), the DB file and its WAL/SHM sidecars are deleted and
    /// the pool is re-created against a fresh file. A warning is logged.
    public init(path: String) throws {
        // Ensure the parent directory exists.
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true
        )

        var config = Configuration()
        config.busyMode = .timeout(5) // retry up to 5 s instead of failing immediately on lock

        do {
            pool = try DatabasePool(path: path, configuration: config)
            logger.info("Database opened at \(path, privacy: .public)")
        } catch {
            // Stale encrypted file (or other corruption) — wipe and start fresh.
            let desc = error.localizedDescription
            logger.warning("DatabasePool open failed; wiping stale DB and recreating. error=\(desc, privacy: .public)")
            AppDatabase.deleteFiles(at: path)
            do {
                pool = try DatabasePool(path: path, configuration: config)
                logger.info("Fresh database created at \(path, privacy: .public) after wipe.")
            } catch {
                throw DatabaseError.openFailed(error)
            }
        }

        try migrator.migrate(pool)
        logger.info("Migrations complete.")
    }

    // MARK: - Wipe

    /// Deletes the DB file (and WAL/SHM sidecars). Logs the wipe reason to `os.log`.
    ///
    /// Call only after the user has explicitly confirmed the "wipe to start fresh" dialog.
    /// After this returns, callers must construct a fresh `AppDatabase` instance to continue.
    public static func wipe(path: String, reason: String) throws {
        logger.warning("History database wiped: \(reason, privacy: .public)")
        deleteFiles(at: path)
        logger.info("Wipe complete.")
    }

    // MARK: - Migrations

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        // In DEBUG, erase the DB on schema change to catch issues early.
        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("v1-create-tables") { db in
            // history table
            try db.create(table: "history") { table in
                table.column("id", .text).primaryKey()
                table.column("text", .text).notNull()
                table.column("rawText", .text)
                table.column("language", .text).notNull()
                table.column("durationMs", .integer).notNull()
                table.column("timestamp", .double).notNull()
                table.column("appBundleID", .text)
            }
            try db.create(
                index: "idx_history_timestamp",
                on: "history",
                columns: ["timestamp"]
            )

            // settings key-value table
            try db.create(table: "settings") { table in
                table.column("key", .text).primaryKey()
                table.column("value", .text).notNull()
            }
        }

        migrator.registerMigration("v2-history-metadata") { db in
            // cleaned: true when the LLM cleanup step ran; false for raw passthrough.
            // DEFAULT 1 so existing rows (which were LLM-cleaned) are correctly classified.
            try db.alter(table: "history") { table in
                table.add(column: "cleaned", .boolean).notNull().defaults(to: true)
            }
            // charCount: denormalized character count of `text` for cheap aggregation.
            try db.alter(table: "history") { table in
                table.add(column: "charCount", .integer).notNull().defaults(to: 0)
            }
        }

        return migrator
    }

    // MARK: - Temporary File (Testing)

    /// Creates a temporary-file `AppDatabase` for unit tests.
    ///
    /// The database is written to a unique file under the system temp directory.
    /// - Does not touch the Keychain.
    /// - Schema is identical to production (same migrations run).
    ///
    /// Use this in test targets to avoid `AppDatabase.shared` fatalError
    /// when Keychain is unavailable in unsigned test environments.
    public static func makeInMemory() throws -> AppDatabase {
        // DatabasePool requires WAL mode which is unsupported for :memory: paths.
        // Use a uniquely-named temp file instead.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("whiskey-test-\(UUID().uuidString).sqlite")
        return try AppDatabase(path: tmp.path)
    }

    // MARK: - Default Path

    /// `~/Library/Application Support/WhisKey/whiskey.sqlite`
    public static func defaultDatabasePath() -> String {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first! // swiftlint:disable:this force_unwrapping
        let dir = appSupport.appendingPathComponent("WhisKey", isDirectory: true)
        return dir.appendingPathComponent("whiskey.sqlite").path
    }

    // MARK: - Private Helpers

    private static func deleteFiles(at path: String) {
        for filePath in [path, path + "-wal", path + "-shm"] where FileManager.default.fileExists(atPath: filePath) {
            try? FileManager.default.removeItem(atPath: filePath)
        }
    }
}
