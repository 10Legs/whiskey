import Foundation
import GRDB
import os.log

private let logger = Logger(subsystem: "com.whiskey.app", category: "Database")

/// Central database manager. Creates the SQLite file, runs migrations, and
/// vends a `DatabasePool` for use by `HistoryStore` and `SettingsManager`.
public final class AppDatabase: Sendable {

    /// The GRDB connection pool (WAL mode, concurrent readers).
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

    /// Creates (or opens) the database at `path` and runs all pending migrations.
    public init(path: String) throws {
        // Ensure the parent directory exists.
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true
        )

        pool = try DatabasePool(path: path)
        logger.info("Database opened at \(path)")

        try migrator.migrate(pool)
        logger.info("Migrations complete.")
    }

    // MARK: - Migrations

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        // Always run migrations in development to catch schema issues early.
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

        return migrator
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
}
