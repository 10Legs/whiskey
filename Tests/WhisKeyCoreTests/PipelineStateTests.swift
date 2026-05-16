@testable import WhisKeyCore
import XCTest

@MainActor class PipelineStateTests: XCTestCase {

    // Build an isolated pipeline backed by an in-memory database so these tests
    // never touch AppDatabase.shared or the Keychain.
    private func makePipeline() throws -> TranscriptionPipeline {
        let db = try AppDatabase.makeInMemory()
        let settings = SettingsManager(db: db)
        let history = HistoryStore(db: db)
        return TranscriptionPipeline(
            historyStore: history,
            settings: settings
        )
    }

    /// stopAndTranscribe while not recording returns nil without crashing.
    func testStopWhileNotRecordingReturnsNil() async throws {
        let pipeline = try makePipeline()
        let result = await pipeline.stopAndTranscribe()
        XCTAssertNil(result)
    }

    /// onError callback not invoked when stop is called with no active session.
    func testNoErrorCallbackOnIdleStop() async throws {
        let pipeline = try makePipeline()
        var errorCalled = false
        pipeline.onError = { _ in errorCalled = true }
        _ = await pipeline.stopAndTranscribe()
        XCTAssertFalse(errorCalled)
    }
}
