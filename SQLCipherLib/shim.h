// SQLCipher shim for GRDB vendored target.
//
// This header includes the SQLCipher sqlite3.h and re-declares the C inline
// helper functions that GRDB normally gets from its bundled CSQLite/shim.h.
//
// SQLITE_HAS_CODEC must be defined before including sqlite3.h so that
// the SQLCipher header exposes sqlite3_key() and sqlite3_rekey() —
// those declarations are gated on #ifdef SQLITE_HAS_CODEC in the header.
//
// Required: brew install sqlcipher

#ifndef SQLITE_HAS_CODEC
#define SQLITE_HAS_CODEC
#endif

#include "/opt/homebrew/opt/sqlcipher/include/sqlcipher/sqlite3.h"

// sqlite3_config and sqlite3_db_config are variadic — Swift cannot call them
// directly. These static inline wrappers expose the specific variants GRDB needs.

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
