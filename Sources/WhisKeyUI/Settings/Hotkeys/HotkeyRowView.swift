import SwiftUI
import WhisKeyCore

/// A single row in the Hotkeys settings table.
///
/// Manages five display states per spec §8:
/// Unbound | Bound | Recording | Conflict | Confirmed.
struct HotkeyRowView: View {

    let action: HotkeyAction
    @ObservedObject var viewModel: HotkeySettingsViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Derived state

    private var currentBinding: HotkeyBinding { viewModel.binding(for: action) }
    private var rowState: RowRecordingState { viewModel.rowState(for: action) }
    private var isRecording: Bool {
        if case .recording = rowState { return true }
        if case .conflict = rowState { return true }
        return false
    }
    private var isBound: Bool { currentBinding.keyCode != nil }
    private var isOtherRowRecording: Bool {
        viewModel.isAnyRowRecording && viewModel.recordingAction != action
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 12) {
            // Action name column (~180 pt).
            Text(action.displayName)
                .font(.system(size: 13))
                .frame(width: 180, alignment: .leading)
                .lineLimit(1)

            // Binding column (~160 pt).
            bindingCell
                .frame(width: 160, alignment: .leading)

            Spacer(minLength: 0)

            // Controls column.
            if !isRecording {
                controlButtons
            }
        }
        .padding(.vertical, 6)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isRecording)
    }

    // MARK: - Binding cell

    @ViewBuilder
    private var bindingCell: some View {
        switch rowState {
        case .idle, .confirmed:
            VStack(alignment: .leading, spacing: 2) {
                KeyBadgeView(binding: currentBinding)
                if case .confirmed = rowState {
                    confirmedLabel
                }
            }

        case .recording, .conflict:
            CaptureCellView(
                action: action,
                state: rowState,
                onDismiss: { viewModel.cancelRecording(action: action) }
            )
        }
    }

    // MARK: - Confirmed label

    private var confirmedLabel: some View {
        ConfirmedLabel(action: action, reduceMotion: reduceMotion)
    }

    // MARK: - Control buttons

    private var controlButtons: some View {
        HStack(spacing: 8) {
            recordButton
            clearButton
        }
    }

    private var recordButton: some View {
        let isCapturing = viewModel.recordingAction == action
        let label = isCapturing ? "Cancel" : "Record"
        let a11yLabel = isCapturing
            ? "Cancel hotkey recording for \(action.displayName)"
            : "Record hotkey for \(action.displayName)"
        let a11yHint = isOtherRowRecording
            ? "Another hotkey is being recorded. Finish or cancel it first."
            : nil

        return Button(label) {
            if isCapturing {
                viewModel.cancelRecording(action: action)
            } else {
                viewModel.startRecording(action: action)
            }
        }
        .disabled(isOtherRowRecording)
        .accessibilityLabel(a11yLabel)
        .accessibilityHint(a11yHint ?? "")
        .contentShape(Rectangle())
    }

    private var clearButton: some View {
        Button {
            viewModel.clearBinding(action: action)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 11))
        }
        .disabled(!isBound)
        .opacity(isBound ? 1.0 : 0.35)
        .accessibilityLabel("Clear hotkey for \(action.displayName)")
        .accessibilityHint(isBound ? "" : "No binding is set.")
        .contentShape(Rectangle().size(CGSize(width: 44, height: 44)))
    }
}

// MARK: - Confirmed label with fade-out

private struct ConfirmedLabel: View {

    let action: HotkeyAction
    let reduceMotion: Bool

    @State private var visible = true

    var body: some View {
        Group {
            if visible {
                Text("Binding updated")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
                    .accessibilityLabel("Binding updated for \(action.displayName)")
            }
        }
        .onAppear {
            scheduleDisappearance()
        }
    }

    private func scheduleDisappearance() {
        let displayDuration: Double = reduceMotion ? 3.0 : 2.0
        let fadeDuration: Double = reduceMotion ? 0.0 : 0.5

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(displayDuration))
            if reduceMotion {
                visible = false
            } else {
                withAnimation(.easeOut(duration: fadeDuration)) {
                    visible = false
                }
            }
        }
    }
}
