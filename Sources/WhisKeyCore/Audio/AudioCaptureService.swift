@preconcurrency import AVFoundation
import Combine
import os.lock

/// Errors thrown by AudioCaptureService.
public enum AudioCaptureError: Error, LocalizedError {
    case engineStartFailed(Error)
    case converterCreationFailed
    case alreadyRecording

    public var errorDescription: String? {
        switch self {
        case .engineStartFailed(let err):
            return "AVAudioEngine failed to start: \(err.localizedDescription)"
        case .converterCreationFailed:
            return "Could not create AVAudioConverter for 16 kHz resampling."
        case .alreadyRecording:
            return "A capture session is already in progress."
        }
    }
}

/// Captures microphone audio via AVAudioEngine and resamples to the format
/// expected by whisper.cpp: 16 kHz, mono, Float32.
///
/// Requires Microphone permission (NSMicrophoneUsageDescription in Info.plist).
public final class AudioCaptureService: @unchecked Sendable {

    // MARK: - Configuration

    private static let whisperSampleRate: Double = 16_000
    private static let tapBufferSize: AVAudioFrameCount = 4096

    // MARK: - State

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var pcmBuffer: [Float] = []
    private var isCapturing = false

    // Low-level lock for buffer mutations called from real-time audio thread.
    private var bufferLock = os_unfair_lock()

    // MARK: - Audio Level Publisher

    /// Normalized RMS level in 0.0–1.0, updated on every audio tap callback.
    /// Subscribers should observe on the main thread for UI updates.
    public let audioLevelPublisher = PassthroughSubject<Float, Never>()

    public init() {}

    // MARK: - Public API

    /// Begin capturing microphone input.
    /// - Throws: `AudioCaptureError` on failure.
    public func startCapture() throws {
        guard !isCapturing else { throw AudioCaptureError.alreadyRecording }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let whisperFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.whisperSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioCaptureError.converterCreationFailed
        }

        // Create converter once; reuse across callbacks.
        guard let conv = AVAudioConverter(from: inputFormat, to: whisperFormat) else {
            throw AudioCaptureError.converterCreationFailed
        }
        converter = conv

        os_unfair_lock_lock(&bufferLock)
        pcmBuffer = []
        os_unfair_lock_unlock(&bufferLock)

        inputNode.installTap(
            onBus: 0,
            bufferSize: Self.tapBufferSize,
            format: inputFormat
        ) { [weak self] inBuffer, _ in
            self?.handleAudioBuffer(inBuffer, whisperFormat: whisperFormat)
        }

        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            converter = nil
            throw AudioCaptureError.engineStartFailed(error)
        }

        isCapturing = true
    }

    /// Stop capturing and return the accumulated PCM samples.
    /// - Returns: Float32 array at 16 kHz, mono.
    public func stopCapture() -> [Float] {
        guard isCapturing else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil
        isCapturing = false

        os_unfair_lock_lock(&bufferLock)
        let result = pcmBuffer
        pcmBuffer = []
        os_unfair_lock_unlock(&bufferLock)

        return result
    }

    // MARK: - Private

    private func handleAudioBuffer(_ inBuffer: AVAudioPCMBuffer, whisperFormat: AVAudioFormat) {
        guard let conv = converter else { return }

        // Calculate output frame count proportional to input.
        let inputSampleRate = inBuffer.format.sampleRate
        let ratio = Self.whisperSampleRate / inputSampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(inBuffer.frameLength) * ratio + 1)

        guard let outBuffer = AVAudioPCMBuffer(
            pcmFormat: whisperFormat,
            frameCapacity: outputFrameCapacity
        ) else { return }

        let inputConsumed = OSAllocatedUnfairLock(initialState: false)
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if inputConsumed.withLock({ $0 }) {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            inputConsumed.withLock { $0 = true }
            return inBuffer
        }

        var error: NSError?
        conv.convert(to: outBuffer, error: &error, withInputFrom: inputBlock)

        guard error == nil, let channelData = outBuffer.floatChannelData?[0] else { return }
        let frameCount = Int(outBuffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))

        os_unfair_lock_lock(&bufferLock)
        pcmBuffer.append(contentsOf: samples)
        os_unfair_lock_unlock(&bufferLock)

        // Compute RMS and publish normalized level (0.0–1.0, clamped).
        if frameCount > 0 {
            let sumOfSquares = samples.reduce(0.0) { $0 + $1 * $1 }
            let rms = sqrtf(sumOfSquares / Float(frameCount))
            // Normalize: typical speech RMS sits around 0.01–0.3; scale by 3 and clamp.
            let normalized = min(rms * 3.0, 1.0)
            audioLevelPublisher.send(normalized)
        }
    }
}
