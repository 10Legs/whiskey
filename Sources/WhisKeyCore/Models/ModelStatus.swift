import Foundation
import os.log

private let logger = Logger(subsystem: "com.whiskey.app", category: "ModelStatus")

// MARK: - Per-model state enum

/// Typed state for a single downloadable model.
///
/// Produced by `ModelStatus.state(for:)` by projecting `ModelManager`'s flat
/// observable dictionaries into a single discriminated union.  Views bind to
/// this type rather than reading three separate dictionaries from `ModelManager`.
public enum ModelDownloadState: Equatable {
    /// No file found on disk; download has not been initiated.
    case notDownloaded
    /// Download is active. `progress` is 0.0–1.0.
    case downloading(progress: Double)
    /// File is present on disk at `url`.
    case downloaded(url: URL)
    /// Last download attempt failed with a human-readable message.
    case failed(message: String)

    public static func == (lhs: ModelDownloadState, rhs: ModelDownloadState) -> Bool {
        switch (lhs, rhs) {
        case (.notDownloaded, .notDownloaded):
            return true
        case (.downloading(let lhs), .downloading(let rhs)):
            return lhs == rhs
        case (.downloaded(let lhs), .downloaded(let rhs)):
            return lhs == rhs
        case (.failed(let lhs), .failed(let rhs)):
            return lhs == rhs
        default:
            return false
        }
    }
}

// MARK: - ModelStatus

/// `@Observable` projection of `ModelManager` into per-model typed states.
///
/// Reads `ModelManager.downloadedModels`, `downloadProgress`, and
/// `downloadError` each time `state(for:)` is called.  Because `ModelManager`
/// is itself `@Observable` and `@MainActor`, any SwiftUI view that calls
/// `state(for:)` inside its `body` will automatically re-render when any of
/// those properties change — no additional combine/publisher wiring required.
///
/// ## Usage
/// ```swift
/// let status = ModelStatus(modelManager: modelManager)
/// // Inside a SwiftUI View body:
/// switch status.state(for: model) {
/// case .notDownloaded:  DownloadButton(...)
/// case .downloading(let p): ProgressBar(value: p)
/// case .downloaded:     CheckmarkView()
/// case .failed(let msg): ErrorLabel(msg)
/// }
/// ```
@Observable
@MainActor
public final class ModelStatus {

    private let modelManager: ModelManager

    public init(modelManager: ModelManager) {
        self.modelManager = modelManager
    }

    // MARK: - Public API

    /// Returns the current download state for `model`.
    ///
    /// Priority: downloading > downloaded > failed > notDownloaded.
    public func state(for model: ModelInfo) -> ModelDownloadState {
        if let progress = modelManager.downloadProgress[model.id] {
            return .downloading(progress: progress)
        }
        if modelManager.downloadedModels.contains(model.id) {
            let url = modelManager.modelsDirectory.appendingPathComponent(model.filename)
            return .downloaded(url: url)
        }
        if let error = modelManager.downloadError[model.id] {
            return .failed(message: error)
        }
        return .notDownloaded
    }

    /// Triggers a re-scan of the models directory and refreshes `ModelManager`.
    ///
    /// Call this after the app returns from background or the user dismisses a
    /// file-chooser sheet, in case models were added/removed outside the app.
    public func refresh() {
        modelManager.rescanModelsDirectory()
        logger.info("ModelStatus.refresh() — rescanned models directory.")
    }

    // MARK: - Convenience queries

    /// `true` if at least one ASR model is present on disk.
    public var hasAnyASRModel: Bool {
        ModelManager.availableModels
            .filter { $0.kind == .asr }
            .contains { modelManager.downloadedModels.contains($0.id) }
    }

    /// `true` if at least one LLM model is present on disk.
    public var hasAnyLLMModel: Bool {
        ModelManager.availableModels
            .filter { $0.kind == .llm }
            .contains { modelManager.downloadedModels.contains($0.id) }
    }
}
