@testable import WhisKeyCore
import XCTest

class HistoryEntryTests: XCTestCase {

    func test_historyEntry_initWithDefaults() {
        let entry = HistoryEntry(
            text: "hello world",
            language: "en",
            durationMs: 5000
        )
        XCTAssertEqual(entry.text, "hello world")
        XCTAssertEqual(entry.language, "en")
        XCTAssertEqual(entry.durationMs, 5000)
        XCTAssertNil(entry.rawText)
        XCTAssertNil(entry.appBundleID)
        XCTAssertFalse(entry.id.isEmpty)
    }

    func test_historyEntry_initWithAllFields() {
        let ts = Date.now.timeIntervalSince1970
        let entry = HistoryEntry(
            id: "test-id",
            text: "cleaned",
            rawText: "raw",
            language: "es",
            durationMs: 3000,
            timestamp: ts,
            appBundleID: "com.example.app"
        )
        XCTAssertEqual(entry.id, "test-id")
        XCTAssertEqual(entry.text, "cleaned")
        XCTAssertEqual(entry.rawText, "raw")
        XCTAssertEqual(entry.language, "es")
        XCTAssertEqual(entry.durationMs, 3000)
        XCTAssertEqual(entry.timestamp, ts)
        XCTAssertEqual(entry.appBundleID, "com.example.app")
    }

    func test_historyEntry_from_transcriptionResult() {
        let result = TranscriptionResult(
            text: "hello there",
            durationMs: 2000,
            language: "en"
        )
        let entry = HistoryEntry.from(
            result: result,
            cleanedText: "hello there!",
            appBundleID: "com.apple.mail"
        )
        XCTAssertEqual(entry.text, "hello there!")
        XCTAssertEqual(entry.rawText, "hello there")
        XCTAssertEqual(entry.language, "en")
        XCTAssertEqual(entry.durationMs, 2000)
        XCTAssertEqual(entry.appBundleID, "com.apple.mail")
    }

    func test_historyEntry_isCodable() {
        let entry = HistoryEntry(
            id: "test",
            text: "hello",
            rawText: "helo",
            language: "en",
            durationMs: 1000,
            appBundleID: "com.test"
        )
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        do {
            let encoded = try encoder.encode(entry)
            let decoded = try decoder.decode(HistoryEntry.self, from: encoded)
            XCTAssertEqual(decoded.id, "test")
            XCTAssertEqual(decoded.text, "hello")
            XCTAssertEqual(decoded.rawText, "helo")
        } catch {
            XCTFail("Failed to encode/decode: \(error)")
        }
    }

    func test_historyEntry_conformsToIdentifiable() {
        let entry = HistoryEntry(
            id: "unique-123",
            text: "test",
            language: "en",
            durationMs: 1000
        )
        XCTAssertEqual(entry.id, "unique-123")
    }
}
