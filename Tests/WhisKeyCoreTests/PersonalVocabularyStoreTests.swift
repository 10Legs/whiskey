@testable import WhisKeyCore
import XCTest

// MARK: - PersonalVocabularyStore Tests (S4-T5)
//
// All tests run against an isolated UserDefaults suite so they never pollute
// the host application's standard defaults.
//
// `PersonalVocabularyStore` is @MainActor-isolated; annotating the test class
// runs all methods on the main actor without extra async wrapping.

@MainActor
final class PersonalVocabularyStoreTests: XCTestCase {

    // swiftlint:disable:next implicitly_unwrapped_optional
    private var defaults: UserDefaults!
    // swiftlint:disable:next implicitly_unwrapped_optional
    private var store: PersonalVocabularyStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let suiteName = "com.whiskey.test.vocabulary.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        store = PersonalVocabularyStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removeSuite(named: defaults.description)
        store = nil
        defaults = nil
        super.tearDown()
    }

    // MARK: - Initial state

    func testInitialTermsIsEmpty() {
        XCTAssertTrue(store.terms.isEmpty)
    }

    func testInitialPromptStringIsEmpty() {
        XCTAssertEqual(store.promptString, "")
    }

    // MARK: - Add

    func testAddValidTermAppendsToTerms() throws {
        try store.add("SwiftUI")
        XCTAssertEqual(store.terms, ["SwiftUI"])
    }

    func testAddMultipleTermsPreservesOrder() throws {
        try store.add("Xcode")
        try store.add("WhisKey")
        try store.add("Whisper")
        XCTAssertEqual(store.terms, ["Xcode", "WhisKey", "Whisper"])
    }

    func testAddTrimsWhitespace() throws {
        try store.add("  SwiftUI  ")
        XCTAssertEqual(store.terms.first, "SwiftUI")
    }

    func testAddEmptyTermThrows() {
        XCTAssertThrowsError(try store.add("")) { error in
            XCTAssertEqual(error as? PersonalVocabularyError, .emptyTerm)
        }
    }

    func testAddWhitespaceOnlyTermThrows() {
        XCTAssertThrowsError(try store.add("   ")) { error in
            XCTAssertEqual(error as? PersonalVocabularyError, .emptyTerm)
        }
    }

    // MARK: - Max 50 cap

    func testAddUpToMaxSucceeds() throws {
        for idx in 1...PersonalVocabularyStore.maximumTermCount {
            try store.add("Term\(idx)")
        }
        XCTAssertEqual(store.terms.count, PersonalVocabularyStore.maximumTermCount)
    }

    func testAddingFiftyFirstTermThrowsTooManyTerms() throws {
        for idx in 1...PersonalVocabularyStore.maximumTermCount {
            try store.add("Term\(idx)")
        }
        XCTAssertThrowsError(try store.add("OneMore")) { error in
            guard case PersonalVocabularyError.tooManyTerms(let max) = error else {
                return XCTFail("Expected .tooManyTerms, got \(error)")
            }
            XCTAssertEqual(max, PersonalVocabularyStore.maximumTermCount)
        }
    }

    func testAddingFiftyFirstTermDoesNotMutateTerms() throws {
        for idx in 1...PersonalVocabularyStore.maximumTermCount {
            try store.add("Term\(idx)")
        }
        _ = try? store.add("OneMore")
        XCTAssertEqual(store.terms.count, PersonalVocabularyStore.maximumTermCount)
    }

    // MARK: - Case-insensitive deduplication

    func testAddDuplicateExactCaseThrows() throws {
        try store.add("Xcode")
        XCTAssertThrowsError(try store.add("Xcode")) { error in
            guard case PersonalVocabularyError.duplicateTerm(let existing) = error else {
                return XCTFail("Expected .duplicateTerm, got \(error)")
            }
            XCTAssertEqual(existing, "Xcode")
        }
    }

    func testAddDuplicateLowercaseThrows() throws {
        try store.add("Xcode")
        XCTAssertThrowsError(try store.add("xcode")) { error in
            guard case PersonalVocabularyError.duplicateTerm = error else {
                return XCTFail("Expected .duplicateTerm, got \(error)")
            }
        }
    }

    func testAddDuplicateUppercaseThrows() throws {
        try store.add("Xcode")
        XCTAssertThrowsError(try store.add("XCODE")) { error in
            guard case PersonalVocabularyError.duplicateTerm = error else {
                return XCTFail("Expected .duplicateTerm, got \(error)")
            }
        }
    }

    func testDifferentTermsAreNotDuplicates() throws {
        try store.add("Xcode")
        XCTAssertNoThrow(try store.add("SwiftUI"))
    }

    // MARK: - Remove

    func testRemoveByExactCaseDeletesTerm() throws {
        try store.add("Xcode")
        store.remove("Xcode")
        XCTAssertTrue(store.terms.isEmpty)
    }

    func testRemoveByCaseInsensitiveMatchDeletesTerm() throws {
        try store.add("Xcode")
        store.remove("xcode")
        XCTAssertTrue(store.terms.isEmpty)
    }

    func testRemoveNonExistentTermIsNoop() throws {
        try store.add("Xcode")
        store.remove("Figma")
        XCTAssertEqual(store.terms, ["Xcode"])
    }

    func testRemoveOnlyRemovesMatchedTerm() throws {
        try store.add("Xcode")
        try store.add("SwiftUI")
        store.remove("Xcode")
        XCTAssertEqual(store.terms, ["SwiftUI"])
    }

    // MARK: - promptString

    func testPromptStringIsEmptyWhenNoTerms() {
        XCTAssertEqual(store.promptString, "")
    }

    func testPromptStringIsSingleTermWhenOneTermAdded() throws {
        try store.add("Xcode")
        XCTAssertEqual(store.promptString, "Xcode")
    }

    func testPromptStringIsCommaJoined() throws {
        try store.add("Xcode")
        try store.add("SwiftUI")
        try store.add("WhisKey")
        XCTAssertEqual(store.promptString, "Xcode, SwiftUI, WhisKey")
    }

    // MARK: - Per-term length cap (S5-M2)

    func testTermAtExactlyMaxLengthAccepted() throws {
        let term = String(repeating: "a", count: PersonalVocabularyStore.maximumTermLength)
        XCTAssertNoThrow(try store.add(term))
        XCTAssertEqual(store.terms.first, term)
    }

    func testTermOneOverMaxLengthRejected() {
        let term = String(repeating: "a", count: PersonalVocabularyStore.maximumTermLength + 1)
        XCTAssertThrowsError(try store.add(term)) { error in
            guard case PersonalVocabularyError.termTooLong(let max) = error else {
                return XCTFail("Expected .termTooLong, got \(error)")
            }
            XCTAssertEqual(max, PersonalVocabularyStore.maximumTermLength)
        }
    }

    func testTooLongTermDoesNotMutateStore() {
        let term = String(repeating: "z", count: PersonalVocabularyStore.maximumTermLength + 1)
        _ = try? store.add(term)
        XCTAssertTrue(store.terms.isEmpty)
    }

    // MARK: - Control character filter (S5-M2)

    func testTermWithControlCharInMiddleRejected() {
        XCTAssertThrowsError(try store.add("hel\u{01}lo")) { error in
            XCTAssertEqual(error as? PersonalVocabularyError, .invalidTerm)
        }
    }

    func testTermWithNullByteRejected() {
        XCTAssertThrowsError(try store.add("bad\u{00}term")) { error in
            XCTAssertEqual(error as? PersonalVocabularyError, .invalidTerm)
        }
    }

    func testTermWithDeleteCharRejected() {
        XCTAssertThrowsError(try store.add("bad\u{7F}term")) { error in
            XCTAssertEqual(error as? PersonalVocabularyError, .invalidTerm)
        }
    }

    func testTermWithoutControlCharsAccepted() throws {
        XCTAssertNoThrow(try store.add("ValidTerm123"))
    }

    // MARK: - UserDefaults persistence

    func testTermsPersistedAfterAdd() throws {
        try store.add("Xcode")
        let store2 = PersonalVocabularyStore(defaults: defaults)
        XCTAssertEqual(store2.terms, ["Xcode"])
    }

    func testTermsPersistedAfterRemove() throws {
        try store.add("Xcode")
        try store.add("SwiftUI")
        store.remove("Xcode")
        let store2 = PersonalVocabularyStore(defaults: defaults)
        XCTAssertEqual(store2.terms, ["SwiftUI"])
    }

    func testFreshStoreLoadsEmptyWhenNoDefaultsKey() throws {
        let freshSuite = "com.whiskey.test.vocabulary.fresh.\(UUID().uuidString)"
        let freshDefaults = try XCTUnwrap(UserDefaults(suiteName: freshSuite))
        let freshStore = PersonalVocabularyStore(defaults: freshDefaults)
        XCTAssertTrue(freshStore.terms.isEmpty)
        freshDefaults.removeSuite(named: freshSuite)
    }

    func testRoundTripPreservesOrder() throws {
        let terms = ["Alpha", "Beta", "Gamma", "Delta"]
        for term in terms { try store.add(term) }

        let store2 = PersonalVocabularyStore(defaults: defaults)
        XCTAssertEqual(store2.terms, terms)
    }
}

// MARK: - Equatable conformance for test assertions

extension PersonalVocabularyError: Equatable {
    public static func == (lhs: PersonalVocabularyError, rhs: PersonalVocabularyError) -> Bool {
        switch (lhs, rhs) {
        case (.emptyTerm, .emptyTerm):
            return true
        case (.tooManyTerms(let lhs), .tooManyTerms(let rhs)):
            return lhs == rhs
        case (.duplicateTerm(let lhs), .duplicateTerm(let rhs)):
            return lhs == rhs
        case (.termTooLong(let lhs), .termTooLong(let rhs)):
            return lhs == rhs
        case (.invalidTerm, .invalidTerm):
            return true
        default:
            return false
        }
    }
}
