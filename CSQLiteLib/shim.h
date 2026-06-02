// CSQLite shim for GRDB vendored target (plain SQLite).
//
// Includes the system sqlite3.h and provides the static inline C helpers
// that GRDB uses for variadic sqlite3_config / sqlite3_db_config calls.
// Swift cannot call variadic C functions directly, so GRDB expects these
// wrappers to be available from whichever SQLite module is in scope.

#include <sqlite3.h>

typedef void(*_errorLogCallback)(void *pArg, int iErrCode, const char *zMsg);

static inline void _registerErrorLogCallback(_errorLogCallback callback) {
    sqlite3_config(SQLITE_CONFIG_LOG, callback, 0);
}

#if SQLITE_VERSION_NUMBER >= 3029000
static inline void _disableDoubleQuotedStringLiterals(sqlite3 *db) {
    sqlite3_db_config(db, SQLITE_DBCONFIG_DQS_DDL, 0, (void *)0);
    sqlite3_db_config(db, SQLITE_DBCONFIG_DQS_DML, 0, (void *)0);
}

static inline void _enableDoubleQuotedStringLiterals(sqlite3 *db) {
    sqlite3_db_config(db, SQLITE_DBCONFIG_DQS_DDL, 1, (void *)0);
    sqlite3_db_config(db, SQLITE_DBCONFIG_DQS_DML, 1, (void *)0);
}
#else
static inline void _disableDoubleQuotedStringLiterals(sqlite3 *db) { }
static inline void _enableDoubleQuotedStringLiterals(sqlite3 *db) { }
#endif
