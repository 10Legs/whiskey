@preconcurrency import AVFoundation
import Combine
import CoreAudio
import os.lock

/// Errors thrown by AudioCaptureService.
public enum AudioCaptureError: Error, LocalizedError {
    case engineStartFailed(Error)
    case converterCreationFailed(String)
    case alreadyRecording

    public var errorDescription: String? {
        switch self {
        case .engineStartFailed(let err):
            return "AVAudioEngine failed to start: \(err.localizedDescription)"
        case .converterCreationFailed(let reason):
            return "Could not create AVAudioConverter for 16 kHz resampling: \(reason)"
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

    public static let trailingSilencePadSeconds: Double = 0.7

    // MARK: - State

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var pcmBuffer: [Float] = []
    private var isCapturing = false

    // Low-level lock for buffer mutations called from real-time audio thread.
    private var bufferLock = os_unfair_lock()

    // Fix C: Retained reference to the CoreAudio listener block so it is not
    // deallocated while the service is alive.
    private var defaultDeviceListenerBlock: AudioObjectPropertyListenerBlock?

    // Fix 2: Debounce state for rapid device-change notifications.
    private var restartWorkItem: DispatchWorkItem?
    private var isRestarting = false

    // MARK: - Audio Level Publisher

    /// Normalized RMS level in 0.0–1.0, updated on every audio tap callback.
    /// Subscribers should observe on the main thread for UI updates.
    public let audioLevelPublisher = PassthroughSubject<Float, Never>()

    // MARK: - Raw Audio Buffer Publisher

    /// Emits the hardware-native AVAudioPCMBuffer received from the tap, before
    /// resampling to 16 kHz. Available for future streaming ASR integration.
    public let audioBufferPublisher = PassthroughSubject<AVAudioPCMBuffer, Never>()

    public init() {
        // Fix A: Subscribe to AVAudioEngineConfigurationChange so that when the
        // system reconfigures the engine (e.g. default device change handled by
        // AVFoundation), we automatically restart the tap with fresh formats.
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            self?.handleEngineConfigurationChange()
        }

        // Fix C: Also listen at the CoreAudio level for default-input-device
        // changes. AVAudioEngineConfigurationChange fires reliably on most
        // switches, but the CoreAudio listener catches edge cases (e.g. BT
        // devices that enumerate before AVFoundation is notified).
        installDefaultDeviceListener()
    }

    deinit {
        // Fix C: Remove the CoreAudio listener using the same block reference.
        if let block = defaultDeviceListenerBlock {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultInputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                .main,
                block
            )
        }
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public API

    /// Begin capturing microphone input.
    /// - Throws: `AudioCaptureError` on failure.
    public func startCapture() throws {
        guard !isCapturing else { throw AudioCaptureError.alreadyRecording }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Fix 3: Bluetooth device negotiation can leave sampleRate == 0 briefly.
        guard inputFormat.sampleRate > 0 else {
            throw AudioCaptureError.converterCreationFailed(
                "Input sample rate is 0 — device format not ready."
            )
        }

        guard let whisperFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.whisperSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioCaptureError.converterCreationFailed("Could not build 16 kHz AVAudioFormat.")
        }

        // Create converter once; reuse across callbacks.
        guard let conv = AVAudioConverter(from: inputFormat, to: whisperFormat) else {
            throw AudioCaptureError.converterCreationFailed(
                "AVAudioConverter init failed (\(inputFormat.sampleRate) Hz → 16000 Hz)."
            )
        }
        converter = conv

        os_unfair_lock_lock(&bufferLock)
        pcmBuffer = []
        os_unfair_lock_unlock(&bufferLock)

        // Pass nil so AVAudioEngine installs the tap in the node's own native
        // format. Passing a non-nil format that nominally matches the node's
        // output format still raises 'com.apple.coreaudio.avfaudio /
        // Failed to create tap due to format mismatch' on macOS 14+ when the
        // engine has been stopped and restarted — the internal hardware
        // negotiation can shift the format between outputFormat(forBus:) and
        // installTap. Passing nil is the documented way to opt out of format
        // conversion at the tap layer; the converter we already built handles
        // the resample to 16 kHz regardless of the native format delivered.
        inputNode.installTap(
            onBus: 0,
            bufferSize: Self.tapBufferSize,
            format: nil
        ) { [weak self] inBuffer, _ in
            // Emit pre-resample buffer for downstream audio consumers.
            self?.audioBufferPublisher.send(inBuffer)
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

    /// Hard-reset all capture state without returning samples.
    ///
    /// Fix 4: Called by TranscriptionPipeline in error paths to ensure
    /// `AudioCaptureService.isCapturing` and `TranscriptionPipeline.isRecording`
    /// always move together. Safe to call even when not capturing.
    public func reset() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil
        isCapturing = false
        os_unfair_lock_lock(&bufferLock)
        pcmBuffer = []
        os_unfair_lock_unlock(&bufferLock)
    }

    /// Stop capturing and return accumulated PCM samples (Float32, 16 kHz, mono).
    public func stopCapture() -> [Float] {
        guard isCapturing else { return [] }

        // [TIMING] Drain in-flight tap callbacks before removing tap.
        Thread.sleep(forTimeInterval: 0.080)
        FileLogger.shared.log(.info, "[TIMING] Drain complete")

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        FileLogger.shared.log(.info, "[TIMING] Engine stopped")
        converter = nil
        isCapturing = false

        os_unfair_lock_lock(&bufferLock)
        let result = pcmBuffer
        pcmBuffer = []
        os_unfair_lock_unlock(&bufferLock)

        return result
    }

    /// Append `trailingSilencePadSeconds` of low-amplitude dither (16 kHz mono)
    /// to the end of `samples`, giving Whisper enough tail context to finalize
    /// the last token. Must be the final transformation before inference.
    /// Dither (not pure zeros) — pure-zero silence trips Whisper's entropy gate.
    public static func appendTrailingSilencePad(to samples: [Float]) -> [Float] {
        let padCount = Int(trailingSilencePadSeconds * whisperSampleRate)
        var pad = [Float](repeating: 0.0, count: padCount)
        for idx in pad.indices { pad[idx] = Float.random(in: -1e-4...1e-4) }
        return samples + pad
    }

    /// Testable variant of `stopCapture()` that bypasses AVAudioEngine.
    ///
    /// Injects `injectedSamples` as if they were captured PCM and applies the
    /// same drain delay as production `stopCapture()`. The trailing silence pad
    /// is applied downstream by `TranscriptionPipeline`, mirroring production.
    /// Only available in DEBUG / test builds via `@testable import`.
    internal func stopCaptureForTesting(injectedSamples: [Float]) -> [Float] {
        // Mimic the drain sleep.
        Thread.sleep(forTimeInterval: 0.080)
        return injectedSamples
    }

    // MARK: - Private — Device Change Handling

    /// Unified handler called by both the AVFoundation notification (Fix A) and
    /// the CoreAudio property listener (Fix C).
    ///
    /// Fix 2: Debounced — coalesces rapid-fire notifications into a single restart
    /// 300 ms after the last event. A re-entrancy guard (`isRestarting`) prevents
    /// concurrent restarts when the CoreAudio and AVFoundation paths both fire.
    private func handleEngineConfigurationChange() {
        guard isCapturing else { return }
        restartWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.isRestarting else { return }
            self.isRestarting = true
            defer { self.isRestarting = false }
            do {
                try self.restartCapture()
            } catch {
                FileLogger.shared.log(.error, "AudioCaptureService: restartCapture() failed: \(error.localizedDescription)")
            }
        }
        restartWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    // Fix B / Fix 1: Tear down the existing tap/engine state and rebuild everything
    // against the new default input device format.
    //
    // isCapturing is set to false at entry so that any failure path leaves the
    // flag clear. It is only restored to true after engine.start() succeeds,
    // preventing the stuck-flag that causes .alreadyRecording on the next hotkey.
    private func restartCapture() throws {
        // Fix 1: Clear flag first — any throw below leaves it false (safe).
        isCapturing = false

        // Remove tap — ignore errors; it may already be detached by the engine.
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil

        // Re-read the input format — this now reflects the new device.
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Fix 3: BT negotiation can leave sampleRate == 0. Bail and reschedule.
        guard inputFormat.sampleRate > 0 else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.handleEngineConfigurationChange()
            }
            return
        }

        guard let whisperFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.whisperSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioCaptureError.converterCreationFailed("Could not build 16 kHz AVAudioFormat.")
        }

        guard let conv = AVAudioConverter(from: inputFormat, to: whisperFormat) else {
            throw AudioCaptureError.converterCreationFailed(
                "AVAudioConverter init failed (\(inputFormat.sampleRate) Hz → 16000 Hz)."
            )
        }
        converter = conv

        // Same nil-format rationale as startCapture() — see comment there.
        inputNode.installTap(
            onBus: 0,
            bufferSize: Self.tapBufferSize,
            format: nil
        ) { [weak self] inBuffer, _ in
            // Emit pre-resample buffer for downstream audio consumers.
            self?.audioBufferPublisher.send(inBuffer)
            self?.handleAudioBuffer(inBuffer, whisperFormat: whisperFormat)
        }

        try engine.start()
        // Fix 1: Only set true after a successful start.
        isCapturing = true
    }

    // Fix C: Register a CoreAudio property listener for the system default
    // input device. Fires on any input device selection change system-wide.
    private func installDefaultDeviceListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.handleEngineConfigurationChange()
            }
        }

        defaultDeviceListenerBlock = block

        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            .main,
            block
        )

        if status != noErr {
            FileLogger.shared.log(.error, "AudioCaptureService: failed to install CoreAudio default-device listener: \(status)")
        }
    }

    // MARK: - Private — Audio Processing

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
            // Normalize: typical speech RMS sits around 0.01–0.3; scale by 8 and clamp.
            let normalized = min(rms * 8.0, 1.0)
            audioLevelPublisher.send(normalized)
        }
    }
}
