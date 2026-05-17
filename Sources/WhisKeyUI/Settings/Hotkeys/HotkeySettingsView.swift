import SwiftUI
import WhisKeyCore

/// The Hotkeys tab content in the WhisKey Settings window.
///
/// Displays a configurable binding for each `HotkeyAction` and a non-interactive
/// placeholder row for the Sprint-4 "Selection-Aware Rewrite" action.
///
/// Tab order in the Settings window: General → Models → Hotkey → Transcription → AI Cleanup → Privacy
/// (the "Hotkeys" tab inserted after the legacy "Hotkey" tab per spec §1).
public struct HotkeySettingsView: View {

    @StateObject private var viewModel: HotkeySettingsViewModel

    public init(store: HotkeyBindingStore) {
        _viewModel = StateObject(wrappedValue: HotkeySettingsViewModel(store: store))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Section header.
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hotkey Bindings")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Assign global keyboard shortcuts to WhisKey actions.")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }

                // Table.
                VStack(spacing: 0) {
                    ForEach(HotkeyAction.allCases, id: \.self) { action in
                        HotkeyRowView(action: action, viewModel: viewModel)
                        Divider()
                    }
                    placeholderRow
                }
                .background(.quaternary.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.separator, lineWidth: 0.5)
                )

                // Info note.
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Text("Hotkeys take effect immediately. No restart required.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding()
        }
    }

    // MARK: - Placeholder row (Sprint 4)

    private var placeholderRow: some View {
        HStack(spacing: 12) {
            Text("Selection-Aware Rewrite")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 180, alignment: .leading)

            Text("Coming in Sprint 4")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
    }
}
