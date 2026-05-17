import Foundation
import os.log

private let logger = Logger(subsystem: "com.whiskey.app", category: "ModelManager")

// MARK: - ModelInfo

/// Distinguishes the role of a downloadable model file.
public enum ModelKind: String, Sendable {
    /// Whisper ASR model — used for speech-to-text transcription.
    case asr
    /// LLM model — used for post-transcription cleanup via llama.cpp.
    case llm
}

/// Metadata describing a downloadable model.
public struct ModelInfo: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let sizeGB: Double
    public let url: URL
    public let filename: String
    public let kind: ModelKind

    public init(
        id: String,
        name: String,
        sizeGB: Double,
        url: URL,
        filename: String,
        kind: ModelKind
    ) {
        self.id = id
        self.name = name
        self.sizeGB = sizeGB
        self.url = url
        self.filename = filename
        self.kind = kind
    }
}

// MARK: - ModelManager

/// Manages discovery, download, and deletion of local Whisper model files.
///
/// `@Observable` / `@MainActor` — matches `SettingsManager` pattern.
/// Downloads use `URLSession` with per-model `URLSessionDownloadTask` so each
/// download can be individually cancelled. Files are written atomically: the
/// URLSession temp file is moved to the final destination in one `FileManager`
/// call so a partial download never masquerades as a complete model.
@Observable
@MainActor
public final class ModelManager: @unchecked Sendable {

    // MARK: - Available models catalogue

    public static let availableModels: [ModelInfo] = [
        // MARK: ASR — Whisper transcription models
        ModelInfo(
            id: "ggml-tiny.en",
            name: "Whisper Tiny (English, fastest)",
            sizeGB: 0.039,
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin")!, // swiftlint:disable:this force_unwrapping
            filename: "ggml-tiny.en.bin",
            kind: .asr
        ),
        ModelInfo(
            id: "ggml-base.en",
            name: "Whisper Base (English)",
            sizeGB: 0.142,
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin")!, // swiftlint:disable:this force_unwrapping
            filename: "ggml-base.en.bin",
            kind: .asr
        ),
        ModelInfo(
            id: "ggml-small.en",
            name: "Whisper Small (English)",
            sizeGB: 0.488,
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin")!, // swiftlint:disable:this force_unwrapping
            filename: "ggml-small.en.bin",
            kind: .asr
        ),
        // MARK: LLM — AI cleanup model (llama.cpp)
        ModelInfo(
            id: "phi-3.5-mini-q4_k_m",
            name: "Phi-3.5 Mini (AI Cleanup)",
            sizeGB: 2.39,
            url: URL(string: "https://huggingface.co/bartowski/Phi-3.5-mini-instruct-GGUF/resolve/main/Phi-3.5-mini-instruct-Q4_K_M.gguf")!, // swiftlint:disable:this force_unwrapping
            filename: "phi-3.5-mini-q4_k_m.gguf",
            kind: .llm
        )
    ]

    // MARK: - Observable state

    /// IDs of models whose .bin file is present in the models directory.
    public var downloadedModels: [String] = []

    /// Model ID currently selected for transcription. Persisted via SettingsManager.
    public var activeModelID: String? {
        get { settings.activeModelID }
        set { settings.activeModelID = newValue }
    }

    /// Download progress per model: 0.0 – 1.0.
    public var downloadProgress: [String: Double] = [:]

    /// Per-model error message (set on failure, cleared on retry).
    public var downloadError: [String: String] = [:]

    // MARK: - Private state

    private let settings: SettingsManager
    /// Active download tasks keyed by model ID.
    private var activeTasks: [String: URLSessionDownloadTask] = [:]
    /// Delegate bridge (must stay alive for the duration of any download).
    private var delegateBridge: DownloadDelegateBridge?

    // MARK: - Init

    public init(settings: SettingsManager = SettingsManager()) {
        self.settings = settings
        rescanModelsDirectory()
    }

    // MARK: - Public API — Directory

    /// `~/Library/Application Support/WhisKey/Models/`
    public var modelsDirectory: URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first! // swiftlint:disable:this force_unwrapping
        return appSupport
            .appendingPathComponent("WhisKey")
            .appendingPathComponent("Models")
    }

    // MARK: - Public API — Download

    /// Begin downloading `model`. No-op if already downloaded or already in progress.
    public func downloadModel(_ model: ModelInfo) async {
        guard !downloadedModels.contains(model.id) else {
            logger.info("Model \(model.id) already downloaded — skipping.")
            return
        }
        guard activeTasks[model.id] == nil else {
            logger.info("Model \(model.id) download already in progress.")
            return
        }

        // Create models directory if needed.
        do {
            try FileManager.default.createDirectory(
                at: modelsDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            downloadError[model.id] = "Cannot create models directory: \(error.localizedDescription)"
            logger.error("Cannot create models directory: \(error.localizedDescription)")
            return
        }

        downloadError.removeValue(forKey: model.id)
        downloadProgress[model.id] = 0.0

        // Build a dedicated URLSession with a delegate bridge so we get progress
        // callbacks without a completion-handler API (which doesn't support progress).
        let bridge = DownloadDelegateBridge(manager: self, modelID: model.id)
        delegateBridge = bridge
        let session = URLSession(
            configuration: .default,
            delegate: bridge,
            delegateQueue: .main
        )

        let task = session.downloadTask(with: model.url)
        activeTasks[model.id] = task
        task.resume()

        logger.info("Download started for \(model.id) from \(model.url.absoluteString)")
    }

    /// Cancel an in-progress download for `modelID`.
    public func cancelDownload(_ modelID: String) {
        activeTasks[modelID]?.cancel()
        activeTasks.removeValue(forKey: modelID)
        downloadProgress.removeValue(forKey: modelID)
        logger.info("Download cancelled for \(modelID)")
    }

    /// Delete the on-disk .bin file for `modelID`.
    public func deleteModel(_ modelID: String) {
        guard let model = ModelManager.availableModels.first(where: { $0.id == modelID }) else {
            return
        }
        let target = modelsDirectory.appendingPathComponent(model.filename)
        do {
            try FileManager.default.removeItem(at: target)
        } catch {
            logger.error("Failed to delete model \(modelID): \(error.localizedDescription)")
        }
        downloadedModels.removeAll { $0 == modelID }
        if activeModelID == modelID {
            activeModelID = downloadedModels.first
        }
        logger.info("Deleted model \(modelID)")
    }

    // MARK: - Internal callbacks (called from DownloadDelegateBridge on main queue)

    func handleProgress(modelID: String, progress: Double) {
        downloadProgress[modelID] = progress
    }

    func handleCompletion(modelID: String, tempURL: URL, bytesSent: Int64, bytesReceived: Int64) {
        activeTasks.removeValue(forKey: modelID)

        guard let model = ModelManager.availableModels.first(where: { $0.id == modelID }) else {
            return
        }
        let destination = modelsDirectory.appendingPathComponent(model.filename)

        do {
            // Atomic move from URLSession temp location.
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: tempURL, to: destination)
            downloadProgress.removeValue(forKey: modelID)
            if !downloadedModels.contains(modelID) {
                downloadedModels.append(modelID)
            }
            // Auto-select if no model is active.
            if activeModelID == nil {
                activeModelID = modelID
            }
            logger.info("Model \(modelID) download complete and moved to \(destination.path)")

            // Report audited egress to EgressAuditor so NetworkActivityMonitor reflects the download.
            let domain = EgressAuditor.domainOnly(from: model.url)
            Task {
                await EgressAuditor.shared.recordCompleted(
                    destination: domain,
                    bytesSent: bytesSent,
                    bytesReceived: bytesReceived,
                    eventType: .modelDownload
                )
            }
        } catch {
            downloadError[modelID] = "Failed to save model: \(error.localizedDescription)"
            downloadProgress.removeValue(forKey: modelID)
            logger.error("Failed to move model \(modelID): \(error.localizedDescription)")
        }
    }

    func handleError(modelID: String, error: Error) {
        activeTasks.removeValue(forKey: modelID)
        downloadProgress.removeValue(forKey: modelID)
        let message = (error as NSError).code == NSURLErrorCancelled
            ? "Download cancelled."
            : error.localizedDescription
        downloadError[modelID] = message
        logger.error("Download error for \(modelID): \(message)")
    }

    // MARK: - Directory scan

    /// Re-reads the models directory and refreshes `downloadedModels`.
    public func rescanModelsDirectory() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: modelsDirectory.path) else {
            downloadedModels = []
            return
        }
        let found = ModelManager.availableModels.filter { model in
            fm.fileExists(atPath: modelsDirectory.appendingPathComponent(model.filename).path)
        }.map(\.id)
        downloadedModels = found
        logger.info("Models directory scan: \(found.count) model(s) found — \(found.joined(separator: ", "))")
    }
}

// MARK: - URLSession delegate bridge

/// Nonisolated `URLSessionDownloadDelegate` that marshals callbacks onto `@MainActor`.
///
/// `ModelManager` is `@MainActor` so we cannot make it directly conform to
/// `URLSessionDownloadDelegate` (which is called on arbitrary queues). This bridge
/// captures the manager weakly to avoid a retain cycle and forwards events via
/// `DispatchQueue.main.async` so the manager receives them on its required actor.
private final class DownloadDelegateBridge: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {

    private weak var manager: ModelManager?
    private let modelID: String
    /// Running total of bytes received. Updated on progress callbacks; passed to handleCompletion.
    private var totalBytesWritten: Int64 = 0

    init(manager: ModelManager, modelID: String) {
        self.manager = manager
        self.modelID = modelID
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        self.totalBytesWritten = totalBytesWritten
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        let id = modelID
        DispatchQueue.main.async { [weak manager] in
            manager?.handleProgress(modelID: id, progress: progress)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Copy temp file before URLSession deletes it after this delegate returns.
        let tempCopy: URL
        do {
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".bin")
            try FileManager.default.copyItem(at: location, to: tmp)
            tempCopy = tmp
        } catch {
            let id = modelID
            DispatchQueue.main.async { [weak manager] in
                manager?.handleError(modelID: id, error: error)
            }
            return
        }

        let id = modelID
        let bytesSent = downloadTask.countOfBytesSent
        let bytesReceived = totalBytesWritten
        DispatchQueue.main.async { [weak manager] in
            manager?.handleCompletion(
                modelID: id,
                tempURL: tempCopy,
                bytesSent: bytesSent,
                bytesReceived: bytesReceived
            )
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let id = modelID
        DispatchQueue.main.async { [weak manager] in
            manager?.handleError(modelID: id, error: error)
        }
    }
}
