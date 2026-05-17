import SwiftUI
import WhisKeyCore

// Matches the phosphor-green terminal aesthetic used throughout WhisKey UI.
private let phosphorGreen = Color(red: 0, green: 1, blue: 0.533)
private let hudBackground  = Color(red: 0.024, green: 0.031, blue: 0.031)

// MARK: - ModelSettingsView

/// "Models" tab shown inside `SettingsView`.
///
/// Renders all models from `ModelManager.availableModels` grouped by kind
/// (ASR / LLM) with per-model status, progress bars, and download / delete
/// controls.  All mutation is delegated to `ModelManager`; this view is
/// read-only with respect to business logic.
public struct ModelSettingsView: View {

    @State private var modelManager: ModelManager
    @State private var modelStatus: ModelStatus

    public init(modelManager: ModelManager) {
        _modelManager = State(initialValue: modelManager)
        _modelStatus  = State(initialValue: ModelStatus(modelManager: modelManager))
    }

    private var asrModels: [ModelInfo] {
        ModelManager.availableModels.filter { $0.kind == .asr }
    }

    private var llmModels: [ModelInfo] {
        ModelManager.availableModels.filter { $0.kind == .llm }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ModelKindSection(
                    title: "TRANSCRIPTION MODELS (ASR)",
                    subtitle: "Used by Whisper for speech-to-text. Smaller = faster, larger = more accurate.",
                    models: asrModels,
                    modelManager: modelManager,
                    modelStatus: modelStatus
                )

                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(phosphorGreen.opacity(0.2))

                ModelKindSection(
                    title: "AI CLEANUP MODELS (LLM)",
                    subtitle: "Used by llama.cpp to refine transcription output. Optional.",
                    models: llmModels,
                    modelManager: modelManager,
                    modelStatus: modelStatus
                )

                if !modelStatus.hasAnyASRModel {
                    NoModelWarningBanner()
                }
            }
            .padding()
        }
        .background(hudBackground)
        .onAppear { modelStatus.refresh() }
    }
}

// MARK: - ModelKindSection

private struct ModelKindSection: View {
    let title: String
    let subtitle: String
    let models: [ModelInfo]
    @State var modelManager: ModelManager
    @State var modelStatus: ModelStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption)
                .fontDesign(.monospaced)
                .foregroundColor(phosphorGreen.opacity(0.6))

            Text(subtitle)
                .font(.caption2)
                .fontDesign(.monospaced)
                .foregroundColor(phosphorGreen.opacity(0.4))

            Rectangle()
                .frame(height: 1)
                .foregroundColor(phosphorGreen.opacity(0.2))

            ForEach(models) { model in
                ModelDownloadRow(
                    model: model,
                    modelManager: modelManager,
                    modelStatus: modelStatus
                )
                if model.id != models.last?.id {
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(phosphorGreen.opacity(0.08))
                }
            }
        }
    }
}

// MARK: - ModelDownloadRow

private struct ModelDownloadRow: View {
    let model: ModelInfo
    @State var modelManager: ModelManager
    @State var modelStatus: ModelStatus

    private var state: ModelDownloadState { modelStatus.state(for: model) }
    private var isActive: Bool { modelManager.activeModelID == model.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                // Kind badge
                KindBadge(kind: model.kind)

                // Name + size
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(model.name)
                            .font(.body)
                            .fontDesign(.monospaced)
                            .foregroundColor(phosphorGreen)
                        if isActive {
                            Text("ACTIVE")
                                .font(.caption2)
                                .fontDesign(.monospaced)
                                .foregroundColor(hudBackground)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(phosphorGreen)
                        }
                    }
                    Text(sizeLabel)
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundColor(phosphorGreen.opacity(0.5))
                }

                Spacer()

                // Status indicator + action
                statusControls
            }

            // Progress bar (shown during download)
            if case .downloading(let pct) = state {
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .frame(width: geo.size.width, height: 3)
                                .foregroundColor(phosphorGreen.opacity(0.15))
                            Rectangle()
                                .frame(width: geo.size.width * pct, height: 3)
                                .foregroundColor(phosphorGreen)
                        }
                    }
                    .frame(height: 3)
                    .animation(.linear(duration: 0.2), value: pct)

                    Text("\(Int(pct * 100))%  —  \(downloadedSizeLabel(progress: pct))")
                        .font(.caption2)
                        .fontDesign(.monospaced)
                        .foregroundColor(phosphorGreen.opacity(0.5))
                }
            }

            // Error message
            if case .failed(let msg) = state {
                Text(msg)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundColor(.red.opacity(0.8))
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusControls: some View {
        switch state {
        case .notDownloaded:
            Button("DOWNLOAD") {
                Task { await modelManager.downloadModel(model) }
            }
            .buttonStyle(ModelButtonStyle())

        case .downloading:
            Button("CANCEL") {
                modelManager.cancelDownload(model.id)
            }
            .buttonStyle(ModelButtonStyle(destructive: true))

        case .downloaded:
            HStack(spacing: 8) {
                // Checkmark status icon
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(phosphorGreen)
                    .imageScale(.small)

                if model.kind == .asr && !isActive {
                    Button("SET ACTIVE") {
                        modelManager.activeModelID = model.id
                    }
                    .buttonStyle(ModelButtonStyle())
                }

                Button("DELETE") {
                    modelManager.deleteModel(model.id)
                }
                .buttonStyle(ModelButtonStyle(destructive: true))
            }

        case .failed:
            Button("RETRY") {
                Task { await modelManager.downloadModel(model) }
            }
            .buttonStyle(ModelButtonStyle())
        }
    }

    // MARK: - Formatting helpers

    private var sizeLabel: String {
        let mb = model.sizeGB * 1024
        if mb < 100 {
            return String(format: "%.0f MB", mb)
        }
        return String(format: "%.2f GB", model.sizeGB)
    }

    private func downloadedSizeLabel(progress: Double) -> String {
        let downloadedMB = model.sizeGB * 1024 * progress
        let totalMB = model.sizeGB * 1024
        return String(format: "%.0f / %.0f MB", downloadedMB, totalMB)
    }
}

// MARK: - KindBadge

private struct KindBadge: View {
    let kind: ModelKind

    var body: some View {
        Text(kind == .asr ? "ASR" : "LLM")
            .font(.caption2)
            .fontDesign(.monospaced)
            .foregroundColor(kind == .asr ? phosphorGreen : Color.cyan)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .overlay(
                Rectangle()
                    .stroke(
                        (kind == .asr ? phosphorGreen : Color.cyan).opacity(0.5),
                        lineWidth: 1
                    )
            )
    }
}

// MARK: - NoModelWarningBanner

private struct NoModelWarningBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.yellow)
            Text("No ASR model downloaded. WhisKey cannot transcribe until at least one ASR model is present.")
                .font(.caption)
                .fontDesign(.monospaced)
                .foregroundColor(.yellow.opacity(0.85))
        }
        .padding(10)
        .overlay(
            Rectangle()
                .stroke(Color.yellow.opacity(0.4), lineWidth: 1)
        )
    }
}

// MARK: - ModelButtonStyle

private struct ModelButtonStyle: ButtonStyle {
    var destructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption)
            .fontDesign(.monospaced)
            .foregroundColor(
                (destructive ? Color.red : phosphorGreen)
                    .opacity(configuration.isPressed ? 0.6 : 1.0)
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .overlay(
                Rectangle()
                    .stroke(
                        (destructive ? Color.red : phosphorGreen).opacity(0.4),
                        lineWidth: 1
                    )
            )
            .background(hudBackground)
    }
}
