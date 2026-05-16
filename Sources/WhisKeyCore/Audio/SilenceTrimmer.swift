import Foundation

/// Energy-based silence trimmer operating on 16 kHz mono PCM (`[Float]`).
///
/// Pure function, no state, `Sendable`. Designed for use in `TranscriptionPipeline`
/// immediately after `AudioCaptureService.stopCapture()` and before Whisper inference.
///
/// Algorithm:
/// 1. Window input into 20 ms frames (320 samples at 16 kHz).
/// 2. Compute RMS per frame.
/// 3. Derive an adaptive noise floor: 20th-percentile frame RMS, clamped to [0.001, 0.05].
/// 4. Speech threshold = max(noiseFloor × 3.0, 0.01).
/// 5. Locate first and last frames where RMS > threshold (60 ms hangover — 3 consecutive
///    frames must exceed the threshold before the region is considered speech).
/// 6. Pad the speech region by 100 ms (5 frames) on each side to preserve plosives/fricatives.
/// 7. If trimmed length < 200 ms, return an empty array (pipeline short-circuits on empty input).
/// 8. If no speech detected, return the original array unchanged.
public struct SilenceTrimmer: Sendable {

    // MARK: - Constants

    private static let defaultSampleRate: Double = 16_000
    private static let frameDurationSeconds: Double = 0.020      // 20 ms
    private static let hangoverFrames: Int = 3                   // 60 ms
    private static let paddingFrames: Int = 5                    // 100 ms
    private static let minDurationSeconds: Double = 0.200        // 200 ms
    private static let noiseFloorMin: Float = 0.001
    private static let noiseFloorMax: Float = 0.050
    private static let thresholdMultiplier: Float = 3.0
    private static let thresholdMin: Float = 0.010
    private static let percentileIndex: Double = 0.20            // 20th percentile

    // MARK: - Public API

    /// Trim leading and trailing silence from a PCM buffer.
    ///
    /// - Parameters:
    ///   - samples: Mono Float32 PCM at `sampleRate`.
    ///   - sampleRate: Samples per second. Defaults to 16 000 Hz.
    /// - Returns: Trimmed buffer, empty array (< 200 ms speech), or original array (no speech).
    public static func trim(_ samples: [Float], sampleRate: Double = 16_000) -> [Float] {
        let frameSize = Int(sampleRate * frameDurationSeconds)
        guard frameSize > 0, samples.count >= frameSize else { return samples }

        let frameRMS = computeFrameRMS(samples: samples, frameSize: frameSize)
        guard !frameRMS.isEmpty else { return samples }

        let noiseFloor = computeNoiseFloor(frameRMS: frameRMS)
        let threshold = max(noiseFloor * thresholdMultiplier, thresholdMin)

        guard let (firstFrame, lastFrame) = findSpeechBounds(
            frameRMS: frameRMS,
            threshold: threshold,
            hangover: hangoverFrames
        ) else {
            // No speech region found — return original to avoid discarding valid audio.
            return samples
        }

        let paddedFirst = max(0, firstFrame - paddingFrames)
        let paddedLast = min(frameRMS.count - 1, lastFrame + paddingFrames)

        let startSample = paddedFirst * frameSize
        let endSample = min(samples.count, (paddedLast + 1) * frameSize)

        let minSamples = Int(sampleRate * minDurationSeconds)
        guard (endSample - startSample) >= minSamples else { return [] }

        return Array(samples[startSample..<endSample])
    }

    // MARK: - Internal Helpers

    static func computeFrameRMS(samples: [Float], frameSize: Int) -> [Float] {
        var result: [Float] = []
        result.reserveCapacity(samples.count / frameSize)
        var offset = 0
        while offset + frameSize <= samples.count {
            let frame = samples[offset..<(offset + frameSize)]
            let sumOfSquares = frame.reduce(0.0) { $0 + $1 * $1 }
            result.append(sqrtf(sumOfSquares / Float(frameSize)))
            offset += frameSize
        }
        return result
    }

    static func computeNoiseFloor(frameRMS: [Float]) -> Float {
        let sorted = frameRMS.sorted()
        let index = Int(Double(sorted.count - 1) * percentileIndex)
        let raw = sorted[index]
        return min(max(raw, noiseFloorMin), noiseFloorMax)
    }

    /// Returns (firstSpeechFrame, lastSpeechFrame) using a hangover detector.
    /// A run of `hangover` consecutive frames above threshold is required before
    /// marking the region as speech, avoiding single-frame noise spikes.
    static func findSpeechBounds(
        frameRMS: [Float],
        threshold: Float,
        hangover: Int
    ) -> (Int, Int)? {
        var firstFrame: Int?
        var lastFrame: Int?
        var consecutiveCount = 0

        for (index, rms) in frameRMS.enumerated() {
            if rms > threshold {
                consecutiveCount += 1
                if consecutiveCount >= hangover {
                    // Mark the start of this run (backtrack to the first frame of the run).
                    if firstFrame == nil {
                        firstFrame = index - (hangover - 1)
                    }
                    lastFrame = index
                }
            } else {
                consecutiveCount = 0
            }
        }

        guard let first = firstFrame, let last = lastFrame else { return nil }
        return (first, last)
    }
}
