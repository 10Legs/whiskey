// swiftlint:disable file_length
import AppKit
import Combine
import SwiftUI
import WhisKeyCore

// MARK: - Pipeline State

/// Observable pipeline state fed into MenuBarView from AppDelegate.
@MainActor
public final class PipelineStateModel: ObservableObject {
    @Published public var recordingState: RecordingState = .idle
    @Published public var lastError: PipelineErrorMessage?
    @Published public var audioLevel: Float = 0.0

    private var levelCancellable: AnyCancellable?

    public init() {}

    public func subscribe(toAudioLevel publisher: AnyPublisher<Float, Never>) {
        levelCancellable = publisher
            .receive(on: RunLoop.main)
            .sink { [weak self] level in self?.audioLevel = level }
    }

    public func postError(_ message: PipelineErrorMessage) {
        lastError = message
    }

    public func clearError() {
        lastError = nil
    }
}

/// Discrete recording pipeline states reflected in the popover and status icon.
public enum RecordingState: Equatable {
    case idle
    case recording
    case processing
    case error(String)
}

/// A user-facing error message surfaced in the inline banner.
public struct PipelineErrorMessage: Identifiable, Equatable {
    public let id: UUID
    public let text: String
    public let action: ErrorAction?

    public enum ErrorAction: Equatable {
        case openSettings
        case retry
    }

    public init(id: UUID = UUID(), text: String, action: ErrorAction? = nil) {
        self.id = id
        self.text = text
        self.action = action
    }
}

// MARK: - MenuBarView

/// Root popover content — Whisper Glass design.
///
/// 320 × 300 pt, `.regularMaterial` background, semantic colors throughout.
/// No custom palette; no phosphor green.
public struct MenuBarView: View {

    @ObservedObject private var pipelineState: PipelineStateModel
    @StateObject private var viewModel: MenuBarViewModel

    private let onOpenSettings: () -> Void
    private let onClear: () -> Void

    public init(
        historyStore: HistoryStore = HistoryStore(),
        modelManager: ModelManager,
        pipelineState: PipelineStateModel,
        onOpenSettings: @escaping () -> Void,
        onClear: @escaping () -> Void = {}
    ) {
        self.pipelineState = pipelineState
        self.onOpenSettings = onOpenSettings
        self.onClear = onClear
        _viewModel = StateObject(
            wrappedValue: MenuBarViewModel(historyStore: historyStore, modelManager: modelManager)
        )
    }

    public var body: some View {
        ZStack {
            // Material background — draws the frosted blur.
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerView
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                errorBannerView
                    .padding(.horizontal, 16)

                Divider()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                contentArea
                    .padding(.horizontal, 16)

                Spacer(minLength: 0)

                footerView
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                    .padding(.top, 8)
            }
        }
        .frame(width: 320, height: 300)
        .task { await viewModel.loadHistory() }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.fill")
                .font(.system(size: 20))
                .foregroundStyle(.primary)
            Text("WhisKey")
                .font(.system(size: 15, weight: .semibold, design: .default))
                .foregroundStyle(.primary)
            Spacer()
        }
    }

    // MARK: - Content (history or recording overlay or onboarding)

    @ViewBuilder
    private var contentArea: some View {
        switch pipelineState.recordingState {
        case .recording, .processing:
            recordingOverlay
                .transition(.opacity)
        case .idle, .error:
            if viewModel.needsOnboarding {
                onboardingCard
                    .transition(.opacity)
            } else {
                historyList
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Recording Overlay (Task 2)

    private var recordingOverlay: some View {
        VStack(spacing: 10) {
            Spacer()
            if pipelineState.recordingState == .recording {
                WaveformBarsView(audioLevel: pipelineState.audioLevel)
                    .frame(height: 40)
                Text("Recording…")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.regular)
                Text("Transcribing…")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Onboarding Card (Task 4)

    private var onboardingCard: some View {
        VStack(spacing: 10) {
            Spacer()
            RoundedRectangle(cornerRadius: 10)
                .fill(.quaternary)
                .overlay(
                    VStack(spacing: 8) {
                        Text("No model downloaded")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("Open Settings to download a model")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Open Settings \u{2192}") {
                            onOpenSettings()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .padding(.top, 2)
                    }
                    .padding(14)
                )
                .frame(maxWidth: .infinity)
            Spacer()
        }
    }

    // MARK: - History List (Task 1)

    private var historyList: some View {
        VStack(spacing: 6) {
            if viewModel.entries.isEmpty {
                emptyHistoryPlaceholder
            } else {
                ForEach(Array(viewModel.entries.enumerated()), id: \.element.id) { index, entry in
                    HistoryCardView(
                        entry: entry,
                        opacity: index == 0 ? 1.0 : (index == 1 ? 0.7 : 0.5)
                    )
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var emptyHistoryPlaceholder: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "mic.fill")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text("Hold Right Option to record")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Error Banner (Task 5)

    @ViewBuilder
    private var errorBannerView: some View {
        if let error = pipelineState.lastError {
            ErrorBannerView(
                message: error,
                onOpenSettings: onOpenSettings,
                onRetry: { pipelineState.clearError() },
                onDismiss: { pipelineState.clearError() }
            )
            .padding(.bottom, 8)
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Button {
                onOpenSettings()
            } label: {
                Image(systemName: "gear")
                    .font(.system(size: 15))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Settings")
            .keyboardShortcut(",", modifiers: .command)

            Spacer()

            Button {
                Task { await viewModel.clearAll() }
                onClear()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 15))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Clear history")
        }
    }
}

// MARK: - History Card

private struct HistoryCardView: View {

    let entry: HistoryEntry
    let opacity: Double

    @State private var copied = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let relativeFormatter: RelativeDateTimeFormatter = {
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .abbreviated
        return fmt
    }()

    var body: some View {
        Button {
            copyToPasteboard()
        } label: {
            ZStack {
                cardContent
                    .opacity(copied ? 0 : 1)
                if copied {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
        }
        .buttonStyle(CardButtonStyle(reduceMotion: reduceMotion))
        .opacity(opacity)
    }

    private var cardContent: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(entry.text)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(relativeTimestamp)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
        )
    }

    private var relativeTimestamp: String {
        let date = Date(timeIntervalSince1970: entry.timestamp)
        return relativeFormatter.localizedString(for: date, relativeTo: .now)
    }

    private func copyToPasteboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(entry.text, forType: .string)

        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
            copied = true
        }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
                copied = false
            }
        }
    }
}

// MARK: - Card Button Style

private struct CardButtonStyle: ButtonStyle {

    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect((!reduceMotion && configuration.isPressed) ? 0.97 : 1.0)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.1),
                value: configuration.isPressed
            )
    }
}

// MARK: - Waveform Bars (Task 2)

/// Simple bar waveform driven by a normalized audio level (0–1).
private struct WaveformBarsView: View {

    let audioLevel: Float
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let barCount = 9

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: 3, height: barHeight(for: index))
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.1),
                        value: audioLevel
                    )
            }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let center = Double(barCount / 2)
        let distance = abs(Double(index) - center) / center
        let envelope = 1.0 - distance * 0.4
        let base: CGFloat = 4
        let maxHeight: CGFloat = 36
        let level = CGFloat(max(audioLevel, 0.05))
        return base + (maxHeight - base) * level * envelope
    }
}

// MARK: - Error Banner (Task 5)

private struct ErrorBannerView: View {

    let message: PipelineErrorMessage
    let onOpenSettings: () -> Void
    let onRetry: () -> Void
    let onDismiss: () -> Void

    @State private var visible = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if visible {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 13))

                Text(message.text)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let action = message.action {
                    actionButton(for: action)
                }

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.orange.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                    )
            )
            .task {
                try? await Task.sleep(for: .seconds(8))
                dismiss()
            }
        }
    }

    @ViewBuilder
    private func actionButton(for action: PipelineErrorMessage.ErrorAction) -> some View {
        switch action {
        case .openSettings:
            Button("Settings") { onOpenSettings() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
        case .retry:
            Button("Retry") { onRetry() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
        }
    }

    private func dismiss() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            visible = false
        }
        onDismiss()
    }
}

// MARK: - View Model

@MainActor
private final class MenuBarViewModel: ObservableObject {

    @Published var entries: [HistoryEntry] = []
    @Published var needsOnboarding: Bool = false

    private let historyStore: HistoryStore
    private let modelManager: ModelManager

    init(historyStore: HistoryStore, modelManager: ModelManager) {
        self.historyStore = historyStore
        self.modelManager = modelManager
    }

    func loadHistory() async {
        needsOnboarding = modelManager.downloadedModels.isEmpty
        guard !needsOnboarding else { return }
        do {
            entries = try await historyStore.fetchRecent(limit: 3)
        } catch {
            // Degrade gracefully — empty history is acceptable.
        }
    }

    func clearAll() async {
        do {
            try await historyStore.deleteAll()
            entries = []
        } catch {
            // No-op on failure; history remains intact.
        }
    }
}
