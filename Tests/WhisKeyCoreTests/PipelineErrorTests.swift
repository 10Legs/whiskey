import Foundation
import XCTest
@testable import WhisKeyCore

class PipelineErrorTests: XCTestCase {

    func testAlreadyRecordingDescription() {
        let error = PipelineError.alreadyRecording
        XCTAssertEqual(error.errorDescription, "Recording is already in progress.")
    }

    func testNotRecordingDescription() {
        let error = PipelineError.notRecording
        XCTAssertEqual(error.errorDescription, "No recording session is active.")
    }

    func testInjectionSkippedIncludesReason() {
        let error = PipelineError.injectionSkipped("empty text")
        XCTAssertTrue(error.errorDescription?.contains("empty text") == true)
    }

    func testCaptureErrorWrapsUnderlying() {
        struct FakeError: LocalizedError {
            var errorDescription: String? { "device unavailable" }
        }
        let error = PipelineError.captureError(FakeError())
        XCTAssertTrue(error.errorDescription?.contains("device unavailable") == true)
    }

    func testTranscriptionErrorWrapsUnderlying() {
        struct FakeError: LocalizedError {
            var errorDescription: String? { "model not found" }
        }
        let error = PipelineError.transcriptionError(FakeError())
        XCTAssertTrue(error.errorDescription?.contains("model not found") == true)
    }
}
