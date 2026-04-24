import XCTest
@testable import WhisKeyCore

@MainActor class PipelineStateTests: XCTestCase {

    /// stopAndTranscribe while not recording returns nil without crashing.
    func testStopWhileNotRecordingReturnsNil() async {
        let pipeline = TranscriptionPipeline()
        let result = await pipeline.stopAndTranscribe()
        XCTAssertNil(result)
    }

    /// onError callback not invoked when stop is called with no active session.
    func testNoErrorCallbackOnIdleStop() async {
        let pipeline = TranscriptionPipeline()
        var errorCalled = false
        pipeline.onError = { _ in errorCalled = true }
        _ = await pipeline.stopAndTranscribe()
        XCTAssertFalse(errorCalled)
    }
}
