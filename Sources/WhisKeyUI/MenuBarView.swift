import SwiftUI
import WhisKeyCore

private let phosphorGreen = Color(red: 0, green: 1, blue: 0.533)
private let hudBackground  = Color(red: 0.024, green: 0.031, blue: 0.031)

/// Content view displayed inside the NSPopover when the menu bar icon is clicked.
///
/// Shows the most recent transcription and a button to open Settings.
public struct MenuBarView: View {

    @State private var recentEntry: HistoryEntry?
    private let historyStore: HistoryStore
    private let onOpenSettings: () -> Void

    public init(
        historyStore: HistoryStore = HistoryStore(),
        onOpenSettings: @escaping () -> Void
    ) {
        self.historyStore = historyStore
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "waveform.and.mic")
                    .font(.title3)
                    .foregroundColor(phosphorGreen)
                Text("WHISKEY")
                    .font(.headline)
                    .fontDesign(.monospaced)
                    .foregroundColor(phosphorGreen)
                Spacer()
            }

            Rectangle()
                .frame(height: 1)
                .foregroundColor(phosphorGreen.opacity(0.2))

            // Last transcription
            if let entry = recentEntry {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LAST TRANSCRIPTION")
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundColor(phosphorGreen.opacity(0.5))
                    Text(entry.text)
                        .font(.body)
                        .fontDesign(.monospaced)
                        .foregroundColor(phosphorGreen)
                        .lineLimit(4)
                        .textSelection(.enabled)
                    Text(formattedDate(entry.timestamp))
                        .font(.caption2)
                        .fontDesign(.monospaced)
                        .foregroundColor(phosphorGreen.opacity(0.5))
                }
            } else {
                Text("No transcriptions yet.\nHold Right Option to record.")
                    .font(.callout)
                    .fontDesign(.monospaced)
                    .foregroundColor(phosphorGreen.opacity(0.5))
            }

            Rectangle()
                .frame(height: 1)
                .foregroundColor(phosphorGreen.opacity(0.2))

            // Actions
            HStack {
                Button("SETTINGS...") {
                    onOpenSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
                .buttonStyle(PhosphorButtonStyle())

                Spacer()

                Button("QUIT") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
                .buttonStyle(PhosphorButtonStyle())
            }
        }
        .padding()
        .frame(width: 300)
        .background(hudBackground)
        .fontDesign(.monospaced)
        .task {
            await loadRecent()
        }
    }

    private func loadRecent() async {
        do {
            let entries = try await historyStore.fetchRecent(limit: 1)
            recentEntry = entries.first
        } catch {
            // Silently degrade — empty state is acceptable
        }
    }

    private func formattedDate(_ timestamp: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}

// MARK: - Phosphor Button Style

private struct PhosphorButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption)
            .fontDesign(.monospaced)
            .foregroundColor(phosphorGreen.opacity(configuration.isPressed ? 0.6 : 1.0))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .overlay(
                Rectangle()
                    .stroke(phosphorGreen.opacity(0.4), lineWidth: 1)
            )
            .background(hudBackground)
    }
}
