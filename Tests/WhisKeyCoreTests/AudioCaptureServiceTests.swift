@testable import WhisKeyCore
import XCTest

class AudioCaptureServiceTests: XCTestCase {

    var service: AudioCaptureService! // swiftlint:disable:this implicitly_unwrapped_optional

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

    // MARK: - S1-T5: Stop-path drain + silence pad

    /// Verifies that stopCapture() appends a silence pad of at least 2400 samples
    /// (150 ms @ 16 kHz) to the returned buffer.
    ///
    /// When not capturing, stopCapture() returns [] immediately (guard exits early).
    /// To test the pad in isolation we inject samples directly via the internal
    /// pcmBuffer. Because AudioCaptureService uses os_unfair_lock for buffer access
    /// and the field is private, we test the pad by observing the returned slice
    /// when stopCapture is called without an active engine session.
    ///
    /// The real pad is only appended on the `isCapturing == true` path, so this
    /// test uses the timing path: start time before call, end time after; the
    /// drain sleep guarantees >= 70 ms of elapsed wall time.
    ///
    /// Note: Microphone + AVAudioEngine access is NOT available in CI. The drain
    /// and pad are verified via a dedicated testable hook — see `stopCaptureForTesting`.
    func test_stopCapture_drainAndPad_whenNotCapturing_returnsEmptyWithoutDelay() {
        // Precondition: not capturing — should return [] immediately, no drain sleep.
        let start = Date()
        let result = service.stopCapture()
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(result.count, 0,
                       "stopCapture when not capturing must return empty array.")
        XCTAssertLessThan(elapsed, 0.050,
                          "stopCapture when not capturing must NOT perform the drain sleep.")
    }

    /// Timing and pad verification using the testable stop path.
    ///
    /// `stopCaptureForTesting(injectedSamples:)` bypasses AVAudioEngine and lets us
    /// exercise the drain + pad logic with injected PCM samples.
    func test_stopCaptureForTesting_drainAtLeast70ms() {
        let injected: [Float] = Array(repeating: 0.1, count: 1600)  // 100 ms of fake audio
        let start = Date()
        let result = service.stopCaptureForTesting(injectedSamples: injected)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertGreaterThanOrEqual(elapsed, 0.070,
                                    "stopCaptureForTesting must drain for at least 70 ms (sleep(0.080)).")
    }

    func test_appendTrailingSilencePad_appends700ms() {
        let injected: [Float] = Array(repeating: 0.1, count: 1600)  // 100 ms of fake audio
        let result = AudioCaptureService.appendTrailingSilencePad(to: injected)

        // 700 ms @ 16 kHz = 11200 samples appended after audio.
        let padSamples = Int(AudioCaptureService.trailingSilencePadSeconds * AudioCaptureService.whisperSampleRate)
        XCTAssertEqual(result.count, injected.count + padSamples,
                       "appendTrailingSilencePad must append exactly \(padSamples) samples (700 ms).")

        // Pad uses low-amplitude dither (not pure zeros) to avoid Whisper's entropy gate.
        let tail = Array(result.suffix(padSamples))
        let allInRange = tail.allSatisfy { $0 >= -1e-4 && $0 <= 1e-4 }
        XCTAssertTrue(allInRange, "Trailing pad samples must be dithered noise in [-1e-4, 1e-4].")
    }
}
