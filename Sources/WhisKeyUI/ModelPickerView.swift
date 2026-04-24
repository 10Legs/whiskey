import SwiftUI
import WhisKeyCore

private let phosphorGreen = Color(red: 0, green: 1, blue: 0.533)
private let hudBackground  = Color(red: 0.024, green: 0.031, blue: 0.031)

/// Displays downloadable models grouped by kind (ASR and LLM) with
/// download/delete controls and progress feedback.
public struct ModelPickerView: View {

    @State private var modelManager: ModelManager

    public init(modelManager: ModelManager) {
        _modelManager = State(initialValue: modelManager)
    }

    private var asrModels: [ModelInfo] {
        ModelManager.availableModels.filter { $0.kind == .asr }
    }

    private var llmModels: [ModelInfo] {
        ModelManager.availableModels.filter { $0.kind == .llm }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ModelSectionView(title: "TRANSCRIPTION", models: asrModels, modelManager: modelManager)
            Rectangle()
                .frame(height: 1)
                .foregroundColor(phosphorGreen.opacity(0.25))
            ModelSectionView(title: "AI CLEANUP", models: llmModels, modelManager: modelManager)
        }
    }
}

// MARK: - ModelSectionView

private struct ModelSectionView: View {

    let title: String
    let models: [ModelInfo]
    @State var modelManager: ModelManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption2)
                .fontDesign(.monospaced)
                .foregroundColor(phosphorGreen.opacity(0.4))
            ForEach(models) { model in
                ModelRowView(model: model, modelManager: modelManager)
                if model.id != models.last?.id {
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(phosphorGreen.opacity(0.1))
                }
            }
        }
    }
}

// MARK: - ModelRowView

private struct ModelRowView: View {

    let model: ModelInfo
    @State var modelManager: ModelManager

    private var isDownloaded: Bool { modelManager.downloadedModels.contains(model.id) }
    private var isActive: Bool { modelManager.activeModelID == model.id }
    private var progress: Double? { modelManager.downloadProgress[model.id] }
    private var errorMessage: String? { modelManager.downloadError[model.id] }
    private var isDownloading: Bool { progress != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                // Name + size
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(model.name)
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

                // Action buttons
                if isDownloaded {
                    HStack(spacing: 8) {
                        if !isActive {
                            Button("SET ACTIVE") {
                                modelManager.activeModelID = model.id
                            }
                            .buttonStyle(PhosphorButtonStyle())
                        }
                        Button("DELETE") {
                            modelManager.deleteModel(model.id)
                        }
                        .buttonStyle(PhosphorButtonStyle(destructive: true))
                    }
                } else if isDownloading {
                    Button("CANCEL") {
                        modelManager.cancelDownload(model.id)
                    }
                    .buttonStyle(PhosphorButtonStyle(destructive: true))
                } else {
                    Button("DOWNLOAD") {
                        Task {
                            await modelManager.downloadModel(model)
                        }
                    }
                    .buttonStyle(PhosphorButtonStyle())
                }
            }

            // Progress bar
            if let pct = progress {
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

                Text("\(Int(pct * 100))% — \(downloadedSizeLabel(progress: pct))")
                    .font(.caption2)
                    .fontDesign(.monospaced)
                    .foregroundColor(phosphorGreen.opacity(0.5))
            }

            // Error message
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundColor(.red.opacity(0.8))
            }
        }
        .padding(.vertical, 4)
    }

    private var sizeLabel: String {
        let mb = model.sizeGB * 1024
        return String(format: "%.0f MB", mb)
    }

    private func downloadedSizeLabel(progress: Double) -> String {
        let downloadedMB = model.sizeGB * 1024 * progress
        let totalMB = model.sizeGB * 1024
        return String(format: "%.0f / %.0f MB", downloadedMB, totalMB)
    }
}

// MARK: - Shared button style

private struct PhosphorButtonStyle: ButtonStyle {
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
