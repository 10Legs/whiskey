// Export the underlying SQLite library.
// GRDBCIPHER is checked first so that the SQLCipher path takes priority
// even when compiled as a Swift Package (where SWIFT_PACKAGE is always set).
// This file is patched from the upstream GRDB 6.29.3 original.
#if GRDBCIPHER
@_exported import SQLCipher
#elseif SWIFT_PACKAGE
@_exported import CSQLite
#elseif !GRDBCUSTOMSQLITE
@_exported import SQLite3
#endif
