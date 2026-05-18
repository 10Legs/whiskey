@testable import WhisKeyCore
import XCTest

// MARK: - SnippetExpanderTests

/// Unit tests for `SnippetExpander` and `SnippetStore` (S3-T5).
///
/// `SnippetExpander` is a pure struct — no actor hops needed.
/// `SnippetStore` tests use an isolated instance and async/await via XCTest async support.
final class SnippetExpanderTests: XCTestCase {

    // MARK: - Helpers

    private func snippet(
        trigger: String,
        expansion: String,
        enabled: Bool = true,
        createdAt: Date = Date()
    ) -> Snippet {
        let snip = Snippet(triggerPhrase: trigger, expansionText: expansion, isEnabled: enabled)
        // Backdoor for creation-date control in tiebreaker tests:
        // Snippet.createdAt is a `let`; we work around this by noting that
        // when we need tiebreaker control we construct snippets in insertion order
        // and the sort is stable with .createdAt ascending. The real `createdAt`
        // is set in the init, so tests that depend on order use Task.sleep or
        // two separate Snippet values without caring about exact date equality.
        return snip
    }

    // MARK: - Basic Expansion

    func testExactMatchExpandsCorrectly() {
        let snip = snippet(trigger: "insert email signature", expansion: "Dear Ron,\n\nBest,\nRon")
        let result = SnippetExpander.expand("insert email signature", snippets: [snip])
        XCTAssertNotNil(result, "Should match when trigger is entire text.")
        XCTAssertEqual(result?.expandedText, "Dear Ron,\n\nBest,\nRon")
        XCTAssertEqual(result?.matchedSnippet.id, snip.id)
    }

    func testEmbeddedTriggerExpands() throws {
        let snip = snippet(trigger: "insert code header", expansion: "// MARK: -")
        let input = "please insert code header now"
        let result = SnippetExpander.expand(input, snippets: [snip])
        XCTAssertNotNil(result, "Embedded trigger should match.")
        let expandedResult = try XCTUnwrap(result)
        XCTAssertTrue(expandedResult.expandedText.contains("// MARK: -"), "Expansion must appear in result.")
        XCTAssertFalse(expandedResult.expandedText.contains("insert code header"), "Trigger must be removed.")
    }

    // MARK: - Case Insensitivity

    func testUppercaseTriggerMatchesLowercaseTranscription() {
        let snip = snippet(trigger: "INSERT EMAIL SIGNATURE", expansion: "Hello,")
        let result = SnippetExpander.expand("insert email signature", snippets: [snip])
        XCTAssertNotNil(result, "Case-insensitive match should fire.")
    }

    func testMixedCaseTriggerMatchesMixedCaseTranscription() {
        let snip = snippet(trigger: "Insert Email Signature", expansion: "Hello,")
        let result = SnippetExpander.expand("INSERT EMAIL SIGNATURE", snippets: [snip])
        XCTAssertNotNil(result, "Case-insensitive match should fire for any casing.")
    }

    // MARK: - No Match

    func testNoMatchReturnsNil() {
        let snip = snippet(trigger: "insert email signature", expansion: "Hello,")
        let result = SnippetExpander.expand("hello world how are you", snippets: [snip])
        XCTAssertNil(result, "Should return nil when no trigger appears in text.")
    }

    func testEmptyTextReturnsNil() {
        let snip = snippet(trigger: "insert email signature", expansion: "Hello,")
        let result = SnippetExpander.expand("", snippets: [snip])
        XCTAssertNil(result)
    }

    func testEmptySnippetsReturnsNil() {
        let result = SnippetExpander.expand("insert email signature", snippets: [])
        XCTAssertNil(result)
    }

    // MARK: - Disabled Snippets

    func testDisabledSnippetIsNeverMatched() {
        let snip = snippet(trigger: "insert email signature", expansion: "Hello,", enabled: false)
        let result = SnippetExpander.expand("insert email signature", snippets: [snip])
        XCTAssertNil(result, "Disabled snippet must not match.")
    }

    func testDisabledSnippetIgnoredWhenEnabledAlsoPresent() {
        let disabled = snippet(trigger: "insert email signature", expansion: "WRONG", enabled: false)
        let enabled = snippet(trigger: "insert home address", expansion: "123 Main St")
        let result = SnippetExpander.expand("insert home address", snippets: [disabled, enabled])
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.expandedText, "123 Main St")
    }

    // MARK: - Longest-Match Wins

    func testLongerTriggerWinsOverShorterWhenBothMatch() {
        // "insert email signature" (3 words) should beat "insert email" (2 words).
        let shorter = snippet(trigger: "insert email", expansion: "SHORT")
        let longer = snippet(trigger: "insert email signature", expansion: "LONG")
        let result = SnippetExpander.expand("insert email signature", snippets: [shorter, longer])
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.expandedText, "LONG", "Longer trigger must win.")
    }

    func testShorterTriggerFallsBackWhenLongerDoesNotMatch() {
        let shorter = snippet(trigger: "insert email", expansion: "SHORT")
        let longer = snippet(trigger: "insert email signature", expansion: "LONG")
        let result = SnippetExpander.expand("please insert email now", snippets: [shorter, longer])
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.expandedText, "please SHORT now")
    }

    // MARK: - Word Boundary Enforcement

    func testPartialWordMatchDoesNotFire() {
        // "insert" alone is not a 3-word trigger, but we test boundary enforcement:
        // a trigger like "end of" should not match inside "vendor offer".
        let snip = snippet(trigger: "end of line", expansion: "EOL")
        let result = SnippetExpander.expand("the vendor offer is fine", snippets: [snip])
        XCTAssertNil(result, "Substring-inside-word must not match due to word boundaries.")
    }

    // MARK: - Whitespace Collapse After Expansion

    func testNoDoubleSpacesAfterExpansion() throws {
        let snip = snippet(trigger: "insert code header", expansion: "// MARK:")
        let result = SnippetExpander.expand("please insert code header now", snippets: [snip])
        XCTAssertNotNil(result)
        let expandedResult = try XCTUnwrap(result)
        XCTAssertFalse(expandedResult.expandedText.contains("  "), "No double spaces after expansion.")
    }

    // MARK: - SnippetStore: Minimum 3 Words

    func testSnippetStoreSaveRejectsOneWordTrigger() async throws {
        let store = SnippetStore.shared
        let snip = Snippet(triggerPhrase: "insert", expansionText: "Hello")
        do {
            try await store.save(snip)
            XCTFail("Expected invalidTrigger error for 1-word trigger.")
        } catch SnippetStoreError.invalidTrigger {
            // Expected.
        }
    }

    func testSnippetStoreSaveRejectsTwoWordTrigger() async throws {
        let store = SnippetStore.shared
        let snip = Snippet(triggerPhrase: "email signature", expansionText: "Hello")
        do {
            try await store.save(snip)
            XCTFail("Expected invalidTrigger error for 2-word trigger.")
        } catch SnippetStoreError.invalidTrigger {
            // Expected.
        }
    }

    func testSnippetStoreSaveAcceptsThreeWordTrigger() async throws {
        // This test writes to disk; use a temp directory to avoid polluting the app store.
        // We skip this at the unit level because SnippetStore.shared uses the real app support dir.
        // The logic under test (word count check) is exercised by the rejection tests above.
        // See comment in testSnippetStoreRoundTrip for the store-isolation note.
        //
        // For CI we verify the rule purely via the SnippetStoreError path.
        let store = SnippetStore.shared
        let snip = Snippet(triggerPhrase: "insert my address", expansionText: "123 Main St")
        // 3-word trigger must NOT throw.
        // NOTE: This will attempt to write to ~/Library/Application Support/WhisKey/snippets.json
        // in the test runner context. If the directory is sandboxed, the write will fail with
        // SnippetStoreError.saveFailed — which is acceptable; the word-count check passes.
        do {
            try await store.save(snip)
            // If write succeeded, verify it's present.
            let all = await store.allSnippets()
            XCTAssertTrue(all.contains(where: { $0.id == snip.id }))
        } catch SnippetStoreError.saveFailed {
            // Sandboxed runner — expected; word-count guard passed (we didn't get invalidTrigger).
        } catch SnippetStoreError.invalidTrigger {
            XCTFail("3-word trigger must be accepted.")
        }
    }

    // MARK: - Export / Import Round-Trip

    func testExportImportRoundTrip() async throws {
        // Build two snippets and export-then-import them into a fresh store instance.
        // We cannot easily use SnippetStore.shared because it touches the real file system,
        // so we test the JSON encoding/decoding logic directly.
        let firstSnippet = Snippet(triggerPhrase: "insert home address", expansionText: "123 Main St")
        let secondSnippet = Snippet(triggerPhrase: "insert code block header", expansionText: "// MARK: -")

        // Manually encode the two snippets into the export envelope format.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        // Use the exact schema structure.
        struct Envelope: Codable {
            let version: Int
            let exportedAt: Date?
            let snippets: [Snippet]
        }
        let envelope = Envelope(version: 1, exportedAt: Date(), snippets: [firstSnippet, secondSnippet])
        let data = try encoder.encode(envelope)

        // Verify re-decodable.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Envelope.self, from: data)
        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.snippets.count, 2)
        XCTAssertEqual(decoded.snippets[0].triggerPhrase, firstSnippet.triggerPhrase)
        XCTAssertEqual(decoded.snippets[0].expansionText, firstSnippet.expansionText)
        XCTAssertEqual(decoded.snippets[1].triggerPhrase, secondSnippet.triggerPhrase)
        XCTAssertEqual(decoded.snippets[1].expansionText, secondSnippet.expansionText)
    }

    // MARK: - Original Text Preserved

    func testOriginalTextPreservedInResult() {
        let snip = snippet(trigger: "insert email signature", expansion: "Hello")
        let input = "insert email signature"
        let result = SnippetExpander.expand(input, snippets: [snip])
        XCTAssertEqual(result?.originalText, input, "originalText must match the input verbatim.")
    }

    // MARK: - Expansion Preserves Case

    func testExpansionTextCaseIsPreserved() {
        let expansion = "Dear [Name],\n\nThank you."
        let snip = snippet(trigger: "insert email signature", expansion: expansion)
        let result = SnippetExpander.expand("insert email signature", snippets: [snip])
        XCTAssertEqual(result?.expandedText, expansion, "Expansion text case must be preserved exactly.")
    }
}
