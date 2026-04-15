import Foundation
import Testing
@testable import WhisKeyCore

@Suite struct PipelineErrorTests {

    @Test func alreadyRecordingDescription() {
        let error = PipelineError.alreadyRecording
        #expect(error.errorDescription == "Recording is already in progress.")
    }

    @Test func notRecordingDescription() {
        let error = PipelineError.notRecording
        #expect(error.errorDescription == "No recording session is active.")
    }

    @Test func injectionSkippedIncludesReason() {
        let error = PipelineError.injectionSkipped("empty text")
        #expect(error.errorDescription?.contains("empty text") == true)
    }

    @Test func captureErrorWrapsUnderlying() {
        struct FakeError: LocalizedError {
            var errorDescription: String? { "device unavailable" }
        }
        let error = PipelineError.captureError(FakeError())
        #expect(error.errorDescription?.contains("device unavailable") == true)
    }

    @Test func transcriptionErrorWrapsUnderlying() {
        struct FakeError: LocalizedError {
            var errorDescription: String? { "model not found" }
        }
        let error = PipelineError.transcriptionError(FakeError())
        #expect(error.errorDescription?.contains("model not found") == true)
    }
}
