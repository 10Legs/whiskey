import AVFoundation

/// Captures microphone audio via AVAudioEngine and buffers PCM data
/// in the format expected by whisper.cpp (16kHz, mono, Float32).
///
/// Requires Microphone permission.
public final class AudioCapturePipeline {
    private let engine = AVAudioEngine()
    private var pcmBuffer: [Float] = []

    public var onBufferReady: (([Float]) -> Void)?

    public init() {}

    public func startCapture() throws {
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // whisper.cpp expects 16kHz mono Float32
        let whisperFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            // TODO: resample inputFormat → whisperFormat if needed
            // For now, collect raw samples
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let samples = Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))
            self?.pcmBuffer.append(contentsOf: samples)
        }

        try engine.start()
    }

    public func stopCapture() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        let result = pcmBuffer
        pcmBuffer = []
        return result
    }
}
