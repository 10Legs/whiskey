import Foundation
import GRDBEncrypted
import os.log

private let logger = Logger(subsystem: "com.whiskey.app", category: "Database")

// MARK: - DatabaseError

/// Errors surfaced by `AppDatabase` startup and wipe operations.
public enum DatabaseError: Error, Sendable {
    /// The DB file exists but the Keychain key is absent.
    /// Do NOT auto-wipe. Present a user-choice dialog:
    ///   "History database unreadable — wipe to start fresh?"
    case keyMissing
    /// Generic open/migrate failure (not key-related).
    case openFailed(Error)
}

// MARK: - AppDatabase

/// Central database manager. Creates the SQLite file, runs migrations, and
/// vends a `DatabasePool` for use by `HistoryStore` and `SettingsManager`.
///
/// ## Startup states
///
/// - **State A:** No DB file + no Keychain key → first launch. Generate key, create DB. Normal.
/// - **State B:** DB file exists + no Keychain key → key lost. Return `DatabaseError.keyMissing`.
///   The app MUST surface this to the user as a recoverable error with an explicit wipe action.
///   Never auto-wipe; the user may have a backup.
/// - **State C:** Keychain key exists + no DB file → key from prior install. Create new DB with
///   the existing key. Normal (previous history was already gone).
public final class AppDatabase: Sendable {

    /// The GRDB connection pool (WAL mode, concurrent readers, SQLCipher-encrypted).
    public let pool: DatabasePool

    // MARK: - Singleton

    /// Shared instance pointing at the default Application Support path.
    /// Crashes on a genuine open failure so the app fails fast rather than silently
    /// corrupting data. Callers that need graceful recovery should use `init(path:)` directly.
    public static let shared: AppDatabase = {
        do {
            let path = AppDatabase.defaultDatabasePath()
            return try AppDatabase(path: path)
        } catch DatabaseError.keyMissing {
            // In DEBUG: auto-wipe the orphaned DB and start fresh (dev data isn't precious).
            // In release: crash — the UI layer must intercept this before shared is accessed.
            #if DEBUG
            let path = AppDatabase.defaultDatabasePath()
            try? AppDatabase.wipe(path: path, reason: "DEBUG: State B recovery — orphaned DB auto-wiped")
            do {
                return try AppDatabase(path: path)
            } catch {
                fatalError("AppDatabase DEBUG recovery failed after wipe: \(error)")
            }
            #else
            fatalError("AppDatabase: Keychain key missing for existing DB — surface DatabaseError.keyMissing to the user")
            #endif
        } catch {
            fatalError("AppDatabase failed to initialize: \(error)")
        }
    }()

    // MARK: - Init

    /// Creates (or opens) the encrypted database at `path`.
    ///
    /// Three-state logic (see type-level docs). Throws `DatabaseError.keyMissing` for State B.
    public init(path: String) throws {
        // Ensure the parent directory exists.
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true
        )

        let keyStore = KeychainKeyStore()
        let dbFileExists = FileManager.default.fileExists(atPath: path)
        let existingKey = try? keyStore.readKey()

        // --- State B: DB file present, key missing → non-recoverable without user action ---
        if dbFileExists && existingKey == nil {
            logger.error("State B: DB file exists at \(path, privacy: .public) but Keychain key is absent. Returning keyMissing error.")
            throw DatabaseError.keyMissing
        }

        // State A: first launch (no file, no key) — getOrCreateKey generates a fresh key.
        // State C: key exists, no DB file — reuse existing key, create new DB file.
        var key = try keyStore.getOrCreateKey()

        // Open the pool with SQLCipher passphrase. The key is passed as raw bytes.
        var config = Configuration()
        config.busyMode = .timeout(5)   // retry up to 5s instead of failing immediately on lock
        config.prepareDatabase { db in
            // Pass key bytes directly. usePassphrase(_:Data) sets PRAGMA key = "x'<hex>'".
            // Enabled by SQLITE_HAS_CODEC compile flag on the GRDBEncrypted target.
            try db.usePassphrase(key)
        }

        do {
            pool = try DatabasePool(path: path, configuration: config)
            logger.info("Encrypted database opened at \(path, privacy: .public)")
        } catch {
            // Zero key before re-throwing to avoid lingering sensitive bytes.
            key.withUnsafeMutableBytes { raw in
                guard let base = raw.baseAddress else { return }
                _ = memset_s(base, raw.count, 0, raw.count)
            }
            throw DatabaseError.openFailed(error)
        }

        // Zero the key immediately after GRDB has consumed it via prepareDatabase.
        key.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            _ = memset_s(base, raw.count, 0, raw.count)
        }

        try migrator.migrate(pool)
        logger.info("Migrations complete.")
    }

    // MARK: - Wipe

    /// Deletes the DB file and Keychain key. Logs the wipe reason to `os.log`.
    ///
    /// Call only after the user has explicitly confirmed the "wipe to start fresh" dialog.
    /// After this returns, callers must construct a fresh `AppDatabase` instance to continue.
    public static func wipe(path: String, reason: String) throws {
        logger.warning("History database wiped: \(reason, privacy: .public)")
        let keyStore = KeychainKeyStore()
        if FileManager.default.fileExists(atPath: path) {
            try FileManager.default.removeItem(atPath: path)
        }
        // Also remove WAL and SHM sidecars if present.
        for suffix in ["-wal", "-shm"] {
            let sidecar = path + suffix
            if FileManager.default.fileExists(atPath: sidecar) {
                try? FileManager.default.removeItem(atPath: sidecar)
            }
        }
        try keyStore.deleteKey()
        logger.info("Wipe complete.")
    }

    // MARK: - Migrations

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        // In DEBUG, erase the DB on schema change to catch issues early.
        // This is NOT a security wipe — it just nukes dev data on schema drift.
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

    /// Creates an **unencrypted** temporary-file `AppDatabase` for unit tests.
    ///
    /// The database is written to a unique file under the system temp directory
    /// and is automatically deleted when the `AppDatabase` object is deallocated.
    ///
    /// - Does not touch the Keychain.
    /// - Schema is identical to production (same migrations run).
    ///
    /// Use this in test targets to avoid `AppDatabase.shared` fatalError
    /// when Keychain is unavailable in unsigned test environments.
    public static func makeInMemory() throws -> AppDatabase {
        // DatabasePool requires WAL mode which is unsupported for :memory: paths.
        // Use a uniquely-named temp file instead. The private init stores the path
        // so it can be removed on deinit.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("whiskey-test-\(UUID().uuidString).sqlite")
        return try AppDatabase(testPath: tmp.path)
    }

    /// Private init for temporary test databases (no Keychain, no SQLCipher passphrase).
    private init(testPath: String) throws {
        pool = try DatabasePool(path: testPath)
        try migrator.migrate(pool)
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
