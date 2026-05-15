@testable import WhisKeyCore
import XCTest

class AudioCaptureServiceTests: XCTestCase {

    var service: AudioCaptureService!

    override func setUp() {
        super.setUp()
        service = AudioCaptureService()
    }

    override func tearDown() {
        service.reset()
        service = nil
        super.tearDown()
    }

    func test_reset_whenNotCapturing_succeeds() {
        service.reset()
    }

    func test_stopCapture_whenNotCapturing_returnsEmptyArray() {
        let samples = service.stopCapture()
        XCTAssertEqual(samples.count, 0)
    }

    func test_startCapture_twice_throwsAlreadyRecordingError() async throws {
        throw XCTSkip("Requires real AVAudioEngine and microphone access")
    }

    func test_stopCapture_clearsIsCapturingFlag() async throws {
        throw XCTSkip("Requires real AVAudioEngine and microphone access")
    }

    func test_reset_clearsIsCapturingFlag() async throws {
        throw XCTSkip("Requires real AVAudioEngine and microphone access")
    }

    func test_audioLevelPublisher_emitValues() async throws {
        throw XCTSkip("Requires real audio data from AVAudioEngine")
    }
}
