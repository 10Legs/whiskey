import Testing
@testable import WhisKeyCore

@MainActor struct PipelineStateTests {

    /// stopAndTranscribe while not recording returns nil without crashing.
    @Test func stopWhileNotRecordingReturnsNil() async {
        let pipeline = TranscriptionPipeline()
        let result = await pipeline.stopAndTranscribe()
        #expect(result == nil)
    }

    /// onError callback not invoked when stop is called with no active session.
    @Test func noErrorCallbackOnIdleStop() async {
        let pipeline = TranscriptionPipeline()
        var errorCalled = false
        pipeline.onError = { _ in errorCalled = true }
        _ = await pipeline.stopAndTranscribe()
        #expect(!errorCalled)
    }
}
