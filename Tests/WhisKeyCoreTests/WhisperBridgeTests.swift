@testable import WhisKeyCore
import XCTest

class WhisperErrorTests: XCTestCase {

    func test_modelNotFoundError_containsPath() {
        let url = URL(fileURLWithPath: "/path/to/model.bin")
        let error = WhisperError.modelNotFound(url)
        XCTAssertTrue(error.errorDescription?.contains("/path/to/model.bin") == true)
    }

    func test_initializationFailedError_hasDescription() {
        let error = WhisperError.initializationFailed
        XCTAssertTrue(error.errorDescription?.contains("Failed to initialize") == true)
    }

    func test_transcriptionFailedError_hasDescription() {
        let error = WhisperError.transcriptionFailed
        XCTAssertTrue(error.errorDescription?.contains("non-zero error") == true)
    }

    func test_emptyAudioError_hasDescription() {
        let error = WhisperError.emptyAudio
        XCTAssertTrue(error.errorDescription?.contains("empty") == true)
    }

    func test_timeoutError_hasDescription() {
        let error = WhisperError.timeout
        XCTAssertTrue(error.errorDescription?.contains("timed out") == true)
    }
}

class WhisperBridgeTests: XCTestCase {

    var bridge: WhisperBridge! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        let tempDir = FileManager.default.temporaryDirectory
        bridge = WhisperBridge(
            modelFileName: "test-model.bin",
            modelDirectoryURL: tempDir,
            nThreads: 2
        )
    }

    override func tearDown() {
        bridge = nil
        super.tearDown()
    }

    func test_whisperBridge_shared_isNotNil() {
        let shared = WhisperBridge.shared
        XCTAssertNotNil(shared)
    }

    func test_whisperBridge_initWithDefaults() {
        let customBridge = WhisperBridge()
        XCTAssertNotNil(customBridge)
    }

    func test_whisperBridge_transcribe_emptyAudio_throwsEmptyAudioError() async {
        do {
            _ = try await bridge.transcribe(pcm: [])
            XCTFail("Expected WhisperError.emptyAudio")
        } catch WhisperError.emptyAudio {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
