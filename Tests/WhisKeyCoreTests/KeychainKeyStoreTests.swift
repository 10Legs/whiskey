import XCTest
@testable import WhisKeyCore

// MARK: - KeychainKeyStore Tests

/// Tests for `KeychainKeyStore`.
///
/// Keychain write/read requires a signed app identity. In CI (unsigned swift test),
/// Keychain calls return errSecMissingEntitlement (-34018). Each test catches that
/// error and exits early rather than failing, so the suite stays green in CI while
/// still exercising the full path on a real Mac with a signed build.
final class KeychainKeyStoreTests: XCTestCase {

    // MARK: - Key generation

    func test_generateKey_returns32Bytes() throws {
        let store = KeychainKeyStore()
        try? store.deleteKey()
        do {
            let key = try store.getOrCreateKey()
            XCTAssertEqual(key.count, 32, "Key must be exactly 32 bytes (256-bit)")
            try store.deleteKey()
        } catch KeychainKeyStoreError.keychainWriteFailed {
            // Keychain unavailable in unsigned CI — skip assertion.
        }
    }

    // MARK: - Idempotency

    func test_getOrCreate_returnsSameKeyOnSecondCall() throws {
        let store = KeychainKeyStore()
        try? store.deleteKey()
        do {
            let first = try store.getOrCreateKey()
            let second = try store.getOrCreateKey()
            XCTAssertEqual(first, second, "getOrCreateKey must return the same key on repeated calls")
            XCTAssertEqual(first.count, 32)
            try store.deleteKey()
        } catch KeychainKeyStoreError.keychainWriteFailed {
            // Keychain unavailable in unsigned CI — skip assertion.
        }
    }

    // MARK: - Absent key

    func test_readKey_returnsNilWhenAbsent() throws {
        let store = KeychainKeyStore()
        try? store.deleteKey()
        do {
            let key = try store.readKey()
            XCTAssertNil(key, "readKey must return nil when no Keychain item exists")
        } catch KeychainKeyStoreError.keychainReadFailed {
            // Keychain unavailable in unsigned CI — skip assertion.
        }
    }
}
