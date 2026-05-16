@testable import WhisKeyCore
import XCTest

class SilenceTrimmerTests: XCTestCase {

    private let sampleRate: Double = 16_000
    private var frameSize: Int { Int(sampleRate * 0.020) } // 320 samples per 20 ms frame

    // MARK: - Helpers

    /// Generate `frames` frames of a pure sine wave at `amplitude`.
    private func sine(frames: Int, amplitude: Float) -> [Float] {
        let total = frames * frameSize
        return (0..<total).map { i in
            amplitude * sin(2 * Float.pi * 440 * Float(i) / Float(sampleRate))
        }
    }

    /// Generate `frames` frames of near-silence (amplitude << noise floor minimum).
    private func silence(frames: Int) -> [Float] {
        Array(repeating: Float(0.0001), count: frames * frameSize)
    }

    // MARK: - All-silence returns original

    func testAllSilenceReturnsOriginal() {
        let silent = silence(frames: 50)
        let result = SilenceTrimmer.trim(silent, sampleRate: sampleRate)
        // No speech detected → return original unchanged.
        XCTAssertEqual(result.count, silent.count,
                       "All-silence buffer should be returned unchanged (no speech region found).")
    }

    // MARK: - Speech preserved

    func testSpeechBufferRetained() {
        // 10 frames silence + 20 frames speech + 10 frames silence
        let samples = silence(frames: 10) + sine(frames: 20, amplitude: 0.5) + silence(frames: 10)
        let result = SilenceTrimmer.trim(samples, sampleRate: sampleRate)
        // Result must be non-empty.
        XCTAssertFalse(result.isEmpty, "Buffer with clear speech should not be trimmed to empty.")
        // Result should be shorter than original (leading/trailing silence removed).
        XCTAssertLessThan(result.count, samples.count,
                          "Trimmed result should be shorter than padded original.")
    }

    func testResultIsSubsetOfOriginal() {
        let samples = silence(frames: 15) + sine(frames: 25, amplitude: 0.6) + silence(frames: 15)
        let result = SilenceTrimmer.trim(samples, sampleRate: sampleRate)
        // All samples in result must appear in the original (trimmer never synthesises audio).
        XCTAssertLessThanOrEqual(result.count, samples.count)
        XCTAssertGreaterThan(result.count, 0)
    }

    // MARK: - Short buffer (< 200 ms) returns empty

    func testShortSpeechBufferReturnsEmpty() {
        // 3 frames of speech (60 ms) with no surrounding silence.
        // The hangover detector (3 consecutive loud frames) is satisfied, so a speech
        // region IS found. Padding clamps to buffer edges (0 silent frames on either
        // side), leaving a 3-frame trimmed region (60 ms) which is below the 200 ms
        // minimum → trim() returns an empty array.
        let samples = sine(frames: 3, amplitude: 0.8)
        let result = SilenceTrimmer.trim(samples, sampleRate: sampleRate)
        XCTAssertTrue(result.isEmpty,
                      "Speech region shorter than 200 ms should return empty array.")
    }

    // MARK: - Padding

    func testLeadingPaddingIsApplied() {
        // Speech starts at frame 10 — trimmer should pad back 5 frames (100 ms).
        let leadingSilence = silence(frames: 10)
        let speech = sine(frames: 30, amplitude: 0.5)
        let samples = leadingSilence + speech
        let result = SilenceTrimmer.trim(samples, sampleRate: sampleRate)
        // Result should include some of the leading silence (padding).
        XCTAssertGreaterThan(result.count, speech.count,
                             "100 ms leading pad should be included in trimmed result.")
    }

    // MARK: - Noise floor adaptation

    func testHighBackgroundNoiseFloorStillDetectsSpeech() {
        // Background noise at amplitude 0.02 (near noise floor ceiling).
        // Speech burst at amplitude 0.3 — well above 3× noise floor.
        let noise: [Float] = (0..<(20 * frameSize)).map { _ in Float.random(in: -0.02...0.02) }
        let speech: [Float] = (0..<(20 * frameSize)).map { _ in Float.random(in: -0.3...0.3) }
        let samples = noise + speech + noise
        let result = SilenceTrimmer.trim(samples, sampleRate: sampleRate)
        XCTAssertFalse(result.isEmpty, "Speech above adaptive noise floor should be detected.")
    }

    // MARK: - Helpers unit tests

    func testComputeFrameRMSBasicValues() {
        // DC signal at amplitude 1.0 → RMS should be 1.0.
        let ones = [Float](repeating: 1.0, count: frameSize)
        let rms = SilenceTrimmer.computeFrameRMS(samples: ones, frameSize: frameSize)
        XCTAssertEqual(rms.count, 1)
        XCTAssertEqual(rms[0], 1.0, accuracy: 0.001)
    }

    func testNoiseFloorClampedToMinimum() {
        // Absolute silence → noise floor should clamp to 0.001.
        let zeros = [Float](repeating: 0.0, count: 100 * frameSize)
        let rms = SilenceTrimmer.computeFrameRMS(samples: zeros, frameSize: frameSize)
        let floor = SilenceTrimmer.computeNoiseFloor(frameRMS: rms)
        XCTAssertGreaterThanOrEqual(floor, 0.001)
    }

    func testFindSpeechBoundsReturnNilOnSilence() {
        let silentRMS = [Float](repeating: 0.0, count: 50)
        let bounds = SilenceTrimmer.findSpeechBounds(frameRMS: silentRMS, threshold: 0.01, hangover: 3)
        XCTAssertNil(bounds, "No speech frames should produce nil bounds.")
    }

    func testFindSpeechBoundsDetectsClearSpeech() {
        // 5 silent frames, then 10 loud frames, then 5 silent.
        var rms = [Float](repeating: 0.001, count: 5)
        rms += [Float](repeating: 0.5, count: 10)
        rms += [Float](repeating: 0.001, count: 5)
        let bounds = SilenceTrimmer.findSpeechBounds(frameRMS: rms, threshold: 0.01, hangover: 3)
        XCTAssertNotNil(bounds)
        XCTAssertEqual(bounds?.0, 5)    // first loud frame
        XCTAssertEqual(bounds?.1, 14)   // last loud frame
    }
}
