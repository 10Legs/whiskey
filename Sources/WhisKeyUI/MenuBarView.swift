import SwiftUI
import WhisKeyCore

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
                Text("WhisKey")
                    .font(.headline)
                Spacer()
            }

            Divider()

            // Last transcription
            if let entry = recentEntry {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last Transcription")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(entry.text)
                        .font(.body)
                        .lineLimit(4)
                        .textSelection(.enabled)
                    Text(formattedDate(entry.timestamp))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text("No transcriptions yet. Hold Right Option to record.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Actions
            HStack {
                Button("Settings...") {
                    onOpenSettings()
                }
                .keyboardShortcut(",", modifiers: .command)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }
        .padding()
        .frame(width: 300)
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
