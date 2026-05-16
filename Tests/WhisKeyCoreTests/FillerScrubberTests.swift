@testable import WhisKeyCore
import XCTest

class FillerScrubberTests: XCTestCase {

    // MARK: - Basic filler removal

    func testRemovesUm() {
        let result = FillerScrubber.scrub("I um need to check that.")
        XCTAssertFalse(result.contains("um"), "\"um\" should be removed.")
    }

    func testRemovesUh() {
        let result = FillerScrubber.scrub("Uh let me think about it.")
        XCTAssertFalse(result.lowercased().contains("uh"), "\"uh\" should be removed.")
    }

    func testRemovesHmm() {
        let result = FillerScrubber.scrub("Hmm, that is interesting.")
        XCTAssertFalse(result.lowercased().contains("hmm"), "\"hmm\" should be removed.")
    }

    func testRemovesEr() {
        let result = FillerScrubber.scrub("We should er consider it.")
        XCTAssertFalse(result.lowercased().contains(" er "), "\"er\" should be removed.")
    }

    func testRemovesAh() {
        let result = FillerScrubber.scrub("Ah right, of course.")
        XCTAssertFalse(result.lowercased().hasPrefix("ah"), "Leading \"ah\" should be removed.")
    }

    // MARK: - Repeated vowel variants

    func testRemovesUmmm() {
        let result = FillerScrubber.scrub("Ummm I think so.")
        XCTAssertFalse(result.lowercased().contains("umm"), "Extended \"umm\" should be removed.")
    }

    func testRemovesUhhh() {
        let result = FillerScrubber.scrub("Uhhh what was I saying.")
        XCTAssertFalse(result.lowercased().contains("uh"), "Extended \"uhh\" should be removed.")
    }

    // MARK: - Case insensitivity

    func testCaseInsensitiveRemoval() {
        let inputs = ["UM hello", "Um hello", "um hello", "uM hello"]
        for input in inputs {
            let result = FillerScrubber.scrub(input)
            XCTAssertFalse(result.lowercased().contains("um"),
                           "Case variant \"\(input)\" should have filler removed.")
        }
    }

    // MARK: - Whitespace normalization

    func testNoDoubleSpacesAfterRemoval() {
        let result = FillerScrubber.scrub("I um need to go.")
        XCTAssertFalse(result.contains("  "), "No double spaces should appear after removal.")
    }

    func testLeadingTrailingWhitespaceTrimmed() {
        let result = FillerScrubber.scrub("  um hello there  ")
        XCTAssertEqual(result, result.trimmingCharacters(in: .whitespaces),
                       "Result should have no leading or trailing whitespace.")
    }

    func testMultipleFillerWords() {
        let result = FillerScrubber.scrub("Um uh I er think ah it is fine.")
        XCTAssertFalse(result.lowercased().contains("um"), "um removed")
        XCTAssertFalse(result.lowercased().contains(" uh "), "uh removed")
        XCTAssertFalse(result.lowercased().contains(" er "), "er removed")
        XCTAssertFalse(result.lowercased().contains(" ah "), "ah removed")
        XCTAssertFalse(result.contains("  "), "No double spaces.")
    }

    // MARK: - Clean text unchanged

    func testCleanTextIsUnchanged() {
        let clean = "This is a clear sentence with no fillers."
        let result = FillerScrubber.scrub(clean)
        XCTAssertEqual(result, clean, "Clean text should pass through unmodified.")
    }

    // MARK: - Empty / edge cases

    func testEmptyStringReturnsEmpty() {
        XCTAssertEqual(FillerScrubber.scrub(""), "")
    }

    func testOnlyFillerWords() {
        let result = FillerScrubber.scrub("um uh er ah")
        XCTAssertTrue(result.trimmingCharacters(in: .whitespaces).isEmpty,
                      "A string of only fillers should reduce to empty.")
    }

    // MARK: - Word boundary enforcement (should NOT remove partial matches)

    func testDoesNotRemoveUmFromInsideWord() {
        // "human" contains "um" but should not be mangled.
        let result = FillerScrubber.scrub("The human said something.")
        XCTAssertTrue(result.contains("human"),
                      "\"human\" must not be altered — \\b enforces word boundary.")
    }

    func testDoesNotRemoveAhFromInsideWord() {
        // "ahead" contains "ah" — must not be removed.
        let result = FillerScrubber.scrub("Look ahead at the road.")
        XCTAssertTrue(result.contains("ahead"),
                      "\"ahead\" must not be altered — \\b enforces word boundary.")
    }
}
