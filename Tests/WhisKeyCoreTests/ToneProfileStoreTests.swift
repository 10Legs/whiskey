@testable import WhisKeyCore
import XCTest

// MARK: - AppToneProfileStore Tests (S4-T7)
//
// All tests use an isolated UserDefaults suite to prevent cross-test and
// cross-session pollution of UserDefaults.standard.
//
// `AppToneProfileStore` is @MainActor-isolated; the class annotation ensures
// every test method runs on the main actor without manual async wrapping.

@MainActor
final class ToneProfileStoreTests: XCTestCase {

    // swiftlint:disable:next implicitly_unwrapped_optional
    private var defaults: UserDefaults!
    // swiftlint:disable:next implicitly_unwrapped_optional
    private var store: AppToneProfileStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let suiteName = "com.whiskey.test.toneprofiles.\(UUID().uuidString)"
        defaults = try XCTUnwrap(
            UserDefaults(suiteName: suiteName),
            "UserDefaults(suiteName:) must not return nil for a fresh UUID suite name."
        )
        store = AppToneProfileStore(defaults: defaults)
    }

    override func tearDown() {
        // Remove the suite so no test data leaks to disk.
        defaults.removePersistentDomain(forName: defaults.description)
        store = nil
        defaults = nil
        super.tearDown()
    }

    // MARK: - Default fallback

    func testDefaultProfileForUnmappedApp() {
        let profile = store.profile(for: "com.unknown.app")
        XCTAssertEqual(profile, .casual, "Unmapped bundle IDs must default to .casual.")
    }

    // MARK: - Set / Get

    func testSetAndGetProfile() throws {
        try store.setProfile(.formal, for: "com.example.word")
        XCTAssertEqual(store.profile(for: "com.example.word"), .formal)
    }

    func testSetOverwritesPreviousProfile() throws {
        try store.setProfile(.formal, for: "com.example.word")
        try store.setProfile(.code, for: "com.example.word")
        XCTAssertEqual(store.profile(for: "com.example.word"), .code,
                       "Second setProfile call must overwrite the first.")
    }

    func testSetRawProfile() throws {
        try store.setProfile(.raw, for: "com.example.terminal")
        XCTAssertEqual(store.profile(for: "com.example.terminal"), .raw)
    }

    // MARK: - Remove

    func testRemoveProfile() throws {
        try store.setProfile(.formal, for: "com.example.word")
        store.removeProfile(for: "com.example.word")
        XCTAssertEqual(store.profile(for: "com.example.word"), .casual,
                       "After removal, bundle ID must revert to the .casual default.")
    }

    func testRemoveNonExistentProfileIsIdempotent() throws {
        try store.setProfile(.formal, for: "com.example.word")
        store.removeProfile(for: "com.unknown.other")
        XCTAssertEqual(store.profile(for: "com.example.word"), .formal,
                       "Removing a non-existent entry must not affect existing mappings.")
    }

    // MARK: - allMappings

    func testAllMappingsEmpty() {
        XCTAssertTrue(store.allMappings.isEmpty, "Fresh store must return empty allMappings.")
    }

    func testAllMappingsSortedByBundleID() throws {
        try store.setProfile(.formal, for: "com.zzz.app")
        try store.setProfile(.code, for: "com.aaa.app")
        try store.setProfile(.casual, for: "com.mmm.app")

        let ids = store.allMappings.map(\.bundleID)
        XCTAssertEqual(ids, ids.sorted(), "allMappings must be sorted ascending by bundle ID.")
    }

    func testAllMappingsContainsCorrectProfiles() throws {
        try store.setProfile(.raw, for: "com.example.terminal")
        try store.setProfile(.formal, for: "com.example.word")

        let mapping = store.allMappings
        XCTAssertEqual(mapping.count, 2)

        let terminalEntry = mapping.first { $0.bundleID == "com.example.terminal" }
        XCTAssertEqual(terminalEntry?.profile, .raw)

        let wordEntry = mapping.first { $0.bundleID == "com.example.word" }
        XCTAssertEqual(wordEntry?.profile, .formal)
    }

    // MARK: - Persistence (save → reload)

    func testPersistenceAcrossStoreReload() throws {
        try store.setProfile(.formal, for: "com.example.word")
        try store.setProfile(.raw, for: "com.example.terminal")

        let reloaded = AppToneProfileStore(defaults: defaults)

        XCTAssertEqual(reloaded.profile(for: "com.example.word"), .formal,
                       "Persisted .formal profile must survive store reload.")
        XCTAssertEqual(reloaded.profile(for: "com.example.terminal"), .raw,
                       "Persisted .raw profile must survive store reload.")
        XCTAssertEqual(reloaded.profile(for: "com.unknown.app"), .casual,
                       "Unmapped app must still default to .casual after reload.")
    }

    func testRemovalPersistedAcrossReload() throws {
        try store.setProfile(.formal, for: "com.example.word")
        store.removeProfile(for: "com.example.word")

        let reloaded = AppToneProfileStore(defaults: defaults)
        XCTAssertEqual(reloaded.profile(for: "com.example.word"), .casual,
                       "Removal must persist: reloaded store must see .casual for removed key.")
    }

    // MARK: - Bundle ID validation (S5-M3)

    func testValidBundleIDAccepted() throws {
        XCTAssertNoThrow(try store.setProfile(.casual, for: "com.apple.Terminal"))
    }

    func testSingleComponentBundleIDRejected() {
        XCTAssertThrowsError(try store.setProfile(.casual, for: "nodot")) { error in
            XCTAssertEqual(error as? AppToneProfileError, .invalidBundleID)
        }
    }

    func testEmptyBundleIDRejected() {
        XCTAssertThrowsError(try store.setProfile(.casual, for: "")) { error in
            XCTAssertEqual(error as? AppToneProfileError, .invalidBundleID)
        }
    }

    func testOversizedBundleIDRejected() {
        let oversized = String(repeating: "a", count: 128) + "." + String(repeating: "b", count: 128)
        XCTAssertThrowsError(try store.setProfile(.casual, for: oversized)) { error in
            guard case AppToneProfileError.bundleIDTooLong(let max) = error else {
                return XCTFail("Expected .bundleIDTooLong, got \(error)")
            }
            XCTAssertEqual(max, AppToneProfileStore.maximumBundleIDLength)
        }
    }

    func testSpecialCharsBundleIDRejected() {
        XCTAssertThrowsError(try store.setProfile(.casual, for: "com.example.app!")) { error in
            XCTAssertEqual(error as? AppToneProfileError, .invalidBundleID)
        }
    }
}

// MARK: - Equatable conformance for test assertions

extension AppToneProfileError: Equatable {
    public static func == (lhs: AppToneProfileError, rhs: AppToneProfileError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidBundleID, .invalidBundleID):
            return true
        case (.bundleIDTooLong(let lhs), .bundleIDTooLong(let rhs)):
            return lhs == rhs
        default:
            return false
        }
    }
}

// MARK: - ToneProfile enum tests

final class ToneProfileTests: XCTestCase {

    func testAllCasesCount() {
        XCTAssertEqual(ToneProfile.allCases.count, 4,
                       "ToneProfile must have exactly 4 cases: casual, formal, code, raw.")
    }

    func testDisplayNames() {
        XCTAssertEqual(ToneProfile.casual.displayName, "Casual")
        XCTAssertEqual(ToneProfile.formal.displayName, "Formal")
        XCTAssertEqual(ToneProfile.code.displayName, "Code")
        XCTAssertEqual(ToneProfile.raw.displayName, "Raw (no cleanup)")
    }

    func testSystemPromptSuffixNonEmptyForNonRaw() {
        for profile in ToneProfile.allCases where profile != .raw {
            XCTAssertFalse(profile.systemPromptSuffix.isEmpty,
                           "\(profile) must have a non-empty systemPromptSuffix.")
        }
    }

    func testRawSystemPromptSuffixIsEmpty() {
        XCTAssertTrue(ToneProfile.raw.systemPromptSuffix.isEmpty,
                      ".raw must have an empty systemPromptSuffix — the LLM is bypassed entirely.")
    }

    func testRoundTripCodable() throws {
        for profile in ToneProfile.allCases {
            let encoded = try JSONEncoder().encode(profile)
            let decoded = try JSONDecoder().decode(ToneProfile.self, from: encoded)
            XCTAssertEqual(decoded, profile, "ToneProfile must round-trip through Codable without loss.")
        }
    }
}
