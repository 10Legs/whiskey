import AVFoundation
import Combine
import Foundation
import Speech

/// Streams partial transcription results using on-device SFSpeechRecognizer.
///
/// Started when recording begins; cancelled on hotkey release.
/// If on-device recognition is unavailable, `start()` returns silently —
/// recording and Whisper batch injection are unaffected.
///
/// Thread safety: all methods must be called on `@MainActor`.
@MainActor
public final class SpeechRecognitionService {

    // MARK: - Published Output

    /// Emits partial transcription strings as the user speaks.
    /// Stops emitting when `stop()` is called.
    public let partialTranscriptPublisher = PassthroughSubject<String, Never>()

    // MARK: - Private State

    private let recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var bufferCancellable: AnyCancellable?

    // MARK: - Init

    public init() {
        let rec = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        self.recognizer = rec
    }

    // MARK: - Public API

    /// Begin streaming recognition from `audioBufferPublisher`.
    ///
    /// Returns immediately without side-effects when:
    /// - Speech recognition authorization is not `.authorized`
    /// - The recognizer is unavailable (offline, locale unsupported, etc.)
    /// - On-device recognition is not supported by this recognizer
    public func start(audioBufferPublisher: AnyPublisher<AVAudioPCMBuffer, Never>) {
        guard let recognizer, recognizer.isAvailable else { return }
        guard recognizer.supportsOnDeviceRecognition else { return }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.requiresOnDeviceRecognition = true
        req.shouldReportPartialResults = true
        self.request = req

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result, !result.isFinal {
                self.partialTranscriptPublisher.send(result.bestTranscription.formattedString)
            }
            if error != nil || result?.isFinal == true {
                self.cleanupTask()
            }
        }

        // Subscribe AFTER task is set; cancel subscription before endAudio in stop().
        bufferCancellable = audioBufferPublisher
            .sink { [weak self] buffer in
                self?.request?.append(buffer)
            }
    }

    /// Stop streaming recognition. Safe to call even when not started.
    ///
    /// Order is critical: cancel the buffer subscription before calling `endAudio()`
    /// to guarantee no `append(_:)` arrives after `endAudio()`, which would crash.
    /// Then cancel the task.
    public func stop() {
        bufferCancellable?.cancel()
        bufferCancellable = nil
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
    }

    // MARK: - Private

    private func cleanupTask() {
        task = nil
        request = nil
    }

    // MARK: - Authorization

    /// Request speech recognition authorization. Completion is called on the main thread.
    public static func requestAuthorization(completion: @escaping @Sendable (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                completion(status == .authorized)
            }
        }
    }
}
