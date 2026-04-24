import Foundation
import XCTest
@testable import WhisKeyCore

class TranscriptionResultTests: XCTestCase {

    func testTextTrimsWhitespace() {
        let result = TranscriptionResult(text: "  hello world  ", durationMs: 100, language: "en")
        XCTAssertEqual(result.text, "hello world")
    }

    func testEmptyTextRemainsEmpty() {
        let result = TranscriptionResult(text: "", durationMs: 0, language: "en")
        XCTAssertEqual(result.text, "")
    }

    func testPropertiesRoundTrip() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        let result = TranscriptionResult(text: "test", durationMs: 500, language: "es", timestamp: date)
        XCTAssertEqual(result.text, "test")
        XCTAssertEqual(result.durationMs, 500)
        XCTAssertEqual(result.language, "es")
        XCTAssertEqual(result.timestamp, date)
    }

    func testWhitespaceOnlyTextBecomesEmpty() {
        let result = TranscriptionResult(text: "   ", durationMs: 50, language: "en")
        XCTAssertEqual(result.text, "")
    }
}
