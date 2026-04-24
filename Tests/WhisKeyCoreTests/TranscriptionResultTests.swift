import Foundation
import Testing
@testable import WhisKeyCore

struct TranscriptionResultTests {

    @Test func textTrimsWhitespace() {
        let result = TranscriptionResult(text: "  hello world  ", durationMs: 100, language: "en")
        #expect(result.text == "hello world")
    }

    @Test func emptyTextRemainsEmpty() {
        let result = TranscriptionResult(text: "", durationMs: 0, language: "en")
        #expect(result.text == "")
    }

    @Test func propertiesRoundTrip() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        let result = TranscriptionResult(text: "test", durationMs: 500, language: "es", timestamp: date)
        #expect(result.text == "test")
        #expect(result.durationMs == 500)
        #expect(result.language == "es")
        #expect(result.timestamp == date)
    }

    @Test func whitespaceOnlyTextBecomesEmpty() {
        let result = TranscriptionResult(text: "   ", durationMs: 50, language: "en")
        #expect(result.text == "")
    }
}
