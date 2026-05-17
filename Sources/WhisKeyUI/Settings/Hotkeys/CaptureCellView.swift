import SwiftUI
import WhisKeyCore

/// The recording-mode cell content shown while a hotkey row is capturing input.
///
/// Spec §3c: rounded rect, `.quaternary` fill, cornerRadius 6.
/// Pulse animation (opacity 1.0 → 0.6 → 1.0, 1.4 s) is suppressed when
/// `prefers-reduced-motion` is active; replaced by a static `.accentColor` border.
struct CaptureCellView: View {

    let action: HotkeyAction
    let state: RowRecordingState
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulseOpacity: Double = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            captureZone
            if case .conflict(_, let message) = state {
                conflictLabel(message: message)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    // MARK: - Capture zone

    @ViewBuilder
    private var captureZone: some View {
        HStack(spacing: 6) {
            captureContent
            Spacer(minLength: 0)
            dismissButton
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(reduceMotion ? Color.accentColor : Color.clear, lineWidth: 1)
                )
        )
        .accessibilityLabel(
            "Recording hotkey for \(action.displayName). " +
            "Press any key combination to assign it, or press Escape to cancel."
        )
        .accessibilityAddTraits(.updatesFrequently)
    }

    @ViewBuilder
    private var captureContent: some View {
        switch state {
        case .recording:
            Text("Press any key…")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .opacity(reduceMotion ? 1.0 : pulseOpacity)
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(
                        .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
                    ) {
                        pulseOpacity = 0.6
                    }
                }

        case .conflict(let comboString, _):
            KeyComboPreviewBadge(comboString: comboString)

        default:
            EmptyView()
        }
    }

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle().size(CGSize(width: 44, height: 44)))
        .accessibilityLabel("Cancel recording")
    }

    // MARK: - Conflict label

    private func conflictLabel(message: String) -> some View {
        Text(message)
            .font(.system(size: 11))
            .foregroundStyle(.orange)
            .accessibilityLabel(message)
            .accessibilityAddTraits(.isStaticText)
    }
}
