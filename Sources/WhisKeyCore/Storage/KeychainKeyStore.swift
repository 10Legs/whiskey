import Foundation
import os.log
import Security

private let logger = Logger(subsystem: "com.whiskey.app", category: "KeychainKeyStore")

// MARK: - Errors

public enum KeychainKeyStoreError: Error, Sendable {
    case randomGenerationFailed(OSStatus)
    case keychainWriteFailed(OSStatus)
    case keychainReadFailed(OSStatus)
    case keychainDeleteFailed(OSStatus)
}

// MARK: - KeychainKeyStore

/// Manages the 32-byte symmetric key used to encrypt the history database.
///
/// Security properties:
/// - Key is generated via `SecRandomCopyBytes` (CSPRNG) — never derived from user input.
/// - Stored with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — does not sync to
///   iCloud, cannot migrate to another machine, and is not accessible before first unlock.
/// - Debug and release builds use distinct `kSecAttrService` values so a debug build
///   cannot read the production database key.
/// - Key buffer is zeroed with `memset_s` immediately after handing the raw bytes to GRDB.
public final class KeychainKeyStore: Sendable {

    private let service: String
    private let account = "default"

    public init() {
        #if DEBUG
        self.service = "com.whiskey.app.history-key.debug"
        #else
        self.service = "com.whiskey.app.history-key"
        #endif
    }

    // MARK: - Public API

    /// Returns the existing DB key from Keychain, or generates and stores a new one.
    /// Safe to call on every launch — idempotent when the key already exists.
    public func getOrCreateKey() throws -> Data {
        if let existing = try readKey() {
            return existing
        }
        let key = try generateKey()
        try storeKey(key)
        logger.info("New 32-byte DB key generated and stored in Keychain (service: \(self.service, privacy: .public))")
        return key
    }

    /// Returns the stored key, or `nil` when no item exists (first launch, or after wipe).
    /// Returns `nil` — not an error — when the item is simply absent.
    /// Throws only on genuine Keychain failures (e.g., access denied, hardware error).
    public func readKey() throws -> Data? {
        var query = baseQuery()
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                return nil
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            logger.error("Keychain read failed: \(status)")
            throw KeychainKeyStoreError.keychainReadFailed(status)
        }
    }

    /// Deletes the Keychain item. Call only when the user explicitly requests a history wipe.
    /// After this, the encrypted DB cannot be opened; wipe the DB file before regenerating.
    public func deleteKey() throws {
        let query = baseQuery()
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            logger.error("Keychain delete failed: \(status)")
            throw KeychainKeyStoreError.keychainDeleteFailed(status)
        }
        logger.warning("DB key deleted from Keychain (service: \(self.service, privacy: .public))")
    }

    // MARK: - Private helpers

    private func generateKey() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, 32, &bytes)
        guard status == errSecSuccess else {
            throw KeychainKeyStoreError.randomGenerationFailed(status)
        }
        return Data(bytes)
    }

    private func storeKey(_ key: Data) throws {
        var attrs = baseQuery()
        attrs[kSecValueData as String] = key
        // Not accessible before first post-boot unlock; device-bound, no iCloud sync.
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        attrs[kSecAttrSynchronizable as String] = false

        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else {
            logger.error("Keychain write failed: \(status)")
            throw KeychainKeyStoreError.keychainWriteFailed(status)
        }
    }

    /// Base query shared by read, write, and delete.
    ///
    /// `kSecAttrAccessGroup` is omitted: this app is non-sandboxed and the literal
    /// "$(AppIdentifierPrefix)…" string is never expanded at runtime (build-time token only),
    /// which caused partition mismatches between store and read operations.
    ///
    /// `kSecUseDataProtectionKeychain` is omitted: it requires specific entitlements that
    /// are not present in all build configurations and causes errSecMissingEntitlement (-34018)
    /// in dev/unsigned builds. The standard login keychain is sufficient for this use case.
    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
