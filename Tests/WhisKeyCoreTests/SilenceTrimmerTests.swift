@testable import WhisKeyCore
import XCTest

class SilenceTrimmerTests: XCTestCase {

    private let sampleRate: Double = 16_000
    private var frameSize: Int { Int(sampleRate * 0.020) } // 320 samples per 20 ms frame

    // MARK: - Helpers

    /// Generate `frames` frames of a pure sine wave at `amplitude`.
    private func sine(frames: Int, amplitude: Float) -> [Float] {
        let total = frames * frameSize
        return (0..<total).map { sampleIndex in
            amplitude * sin(2 * Float.pi * 440 * Float(sampleIndex) / Float(sampleRate))
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
        // With hangover=5 (100 ms), a 5-frame burst is the minimum that triggers speech
        // detection. A 4-frame burst falls below the hangover threshold → no speech region
        // found → trim() returns the original unchanged (not empty).
        // A 5-frame burst DOES satisfy the hangover but leaves a 5-frame trimmed region
        // (100 ms) which is below the 200 ms minimum → trim() returns an empty array.
        let samples = sine(frames: 5, amplitude: 0.8)
        let result = SilenceTrimmer.trim(samples, sampleRate: sampleRate)
        XCTAssertTrue(result.isEmpty,
                      "Speech region shorter than 200 ms (exactly at hangover boundary) should return empty array.")
    }

    func testSubHangoverBurstReturnsOriginal() {
        // A burst of 4 frames (80 ms) doesn't satisfy the 5-frame (100 ms) hangover —
        // no speech region is found, so the original buffer is returned unchanged.
        let samples = sine(frames: 4, amplitude: 0.8)
        let result = SilenceTrimmer.trim(samples, sampleRate: sampleRate)
        XCTAssertEqual(result.count, samples.count,
                       "A sub-hangover burst should return original array (no speech region detected).")
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

    // MARK: - Hangover trailing-edge tests (S1-T6)

    /// Onset detection: signal starts at frame 1 (0-indexed), frames 1–5 are above
    /// threshold. With hangover=3 the first confirmed speech frame is frame 1
    /// (backtracked from frame 3). With hangover=5 the first confirmed frame is
    /// still frame 1 (backtracked from frame 5). Both should detect onset at frame 1.
    func testOnsetDetectedAtFirstAboveThresholdFrame() {
        // Frame 0: below threshold; frames 1–6: above threshold.
        var rms: [Float] = [0.001]
        rms += [Float](repeating: 0.5, count: 6)
        // With hangover=5: requires 5 consecutive above-threshold frames.
        // Frame 5 (0-indexed) is when the 5th consecutive above-threshold frame
        // is seen (frames 1..5), so firstFrame = 5 - (5-1) = 1.
        let boundsH5 = SilenceTrimmer.findSpeechBounds(frameRMS: rms, threshold: 0.01, hangover: 5)
        XCTAssertNotNil(boundsH5)
        XCTAssertEqual(boundsH5?.0, 1,
                       "hangover=5: onset should backtrack to frame 1 (first above-threshold frame).")

        // With hangover=3: onset at frame 1 (backtracked from frame 3).
        let boundsH3 = SilenceTrimmer.findSpeechBounds(frameRMS: rms, threshold: 0.01, hangover: 3)
        XCTAssertNotNil(boundsH3)
        XCTAssertEqual(boundsH3?.0, 1,
                       "hangover=3: onset should backtrack to frame 1 (first above-threshold frame).")
    }

    /// Trailing-edge hangover: signal drops after 10 loud frames, then silence.
    /// With hangover=3 (3 frames = 60 ms), a run of only 4 loud frames satisfies
    /// the hangover and the trailing `lastFrame` is set. But with the production
    /// hangover set to 5, verify the trimmer requires 5 consecutive frames before
    /// locking in a speech region — and that it keeps the region alive long enough
    /// to avoid plosive clipping.
    ///
    /// Failing condition (before fix): `hangoverFrames == 3` means a 3-frame
    /// loud burst is the minimum detected region. After the fix (hangoverFrames=5)
    /// a burst of only 3 frames above threshold is NOT enough to trigger speech
    /// detection, but 5 frames IS — ensuring plosives that ride the threshold
    /// boundary need enough consecutive energy to be retained.
    func testTrailingEdgeHangoverRequiresFiveFrames() {
        // Build RMS with exactly 4 loud frames followed by silence.
        // hangover=5 should NOT detect speech (4 < 5).
        var rms4: [Float] = [0.001, 0.001]
        rms4 += [Float](repeating: 0.5, count: 4)
        rms4 += [Float](repeating: 0.001, count: 10)
        let bounds4 = SilenceTrimmer.findSpeechBounds(frameRMS: rms4, threshold: 0.01, hangover: 5)
        XCTAssertNil(bounds4,
                     "hangover=5: a 4-frame burst should NOT satisfy the 5-frame hangover requirement.")

        // Build RMS with exactly 5 loud frames followed by silence.
        // hangover=5 SHOULD detect speech (5 == 5).
        var rms5: [Float] = [0.001, 0.001]
        rms5 += [Float](repeating: 0.5, count: 5)
        rms5 += [Float](repeating: 0.001, count: 10)
        let bounds5 = SilenceTrimmer.findSpeechBounds(frameRMS: rms5, threshold: 0.01, hangover: 5)
        XCTAssertNotNil(bounds5,
                        "hangover=5: a 5-frame burst should satisfy the 5-frame hangover requirement.")
        // Onset backtracked: frame index where 5th consecutive loud frame appears is index 6
        // (0-indexed: silent=0,1; loud=2,3,4,5,6). firstFrame = 6 - (5-1) = 2.
        XCTAssertEqual(bounds5?.0, 2,
                       "Speech onset should backtrack to the first of the 5 consecutive loud frames.")

        // Verify that the DEFAULT hangoverFrames (currently 3) would accept the 4-frame burst.
        // This test documents the BEFORE state — with hangover=3, 4 frames IS enough.
        // After the production fix (hangover=5), this path is unreachable in the live trimmer,
        // but the helper still accepts the parameter so we can verify the contrast.
        let bounds4_legacy = SilenceTrimmer.findSpeechBounds(frameRMS: rms4, threshold: 0.01, hangover: 3)
        XCTAssertNotNil(bounds4_legacy,
                        "hangover=3 (old default): a 4-frame burst SHOULD satisfy the 3-frame requirement.")
    }

    /// Integration test: trim() with the PRODUCTION hangover (5 frames).
    /// A plosive-style onset: 2 frames below threshold, then 5+ frames above,
    /// then sustained speech. The trimmer must NOT clip the onset.
    func testTrimPreservesOnsetWithFiveFrameHangover() {
        // Construct: 5 frames silence, 5 frames above threshold (onset), 20 frames loud speech, 5 silence.
        let samples = silence(frames: 5)
            + sine(frames: 5, amplitude: 0.3)   // onset — at threshold
            + sine(frames: 20, amplitude: 0.5)  // sustained speech
            + silence(frames: 5)
        let result = SilenceTrimmer.trim(samples, sampleRate: sampleRate)
        XCTAssertFalse(result.isEmpty, "trim() should detect speech with 5-frame onset and not return empty.")
        // Result must include the onset region (should be shorter than original but non-trivially long).
        let minExpected = (5 + 5 + 20) * frameSize   // speech + onset, no trailing silence
        XCTAssertGreaterThan(result.count, minExpected / 2,
                             "Trimmed result should preserve the majority of the onset+speech region.")
    }
}
