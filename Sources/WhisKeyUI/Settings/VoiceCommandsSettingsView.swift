import SwiftUI

private let phosphorGreen = Color(red: 0, green: 1, blue: 0.533)
private let hudBackground  = Color(red: 0.024, green: 0.031, blue: 0.031)

/// Read-only reference view listing every built-in voice command phrase and
/// the action it triggers.  Surfaced as the "Commands" tab in SettingsView.
public struct VoiceCommandsSettingsView: View {

    fileprivate struct CommandEntry: Identifiable {
        let id = UUID()
        let phrases: [String]
        let action: String
        let status: Status

        enum Status {
            case implemented
            case stripped  // phrase stripped, action not yet wired via AX
        }
    }

    private let entries: [CommandEntry] = [
        CommandEntry(
            phrases: ["new paragraph"],
            action: "Inserts two newlines (\\n\\n) at the cursor.",
            status: .implemented
        ),
        CommandEntry(
            phrases: ["new line"],
            action: "Inserts one newline (\\n) at the cursor.",
            status: .implemented
        ),
        CommandEntry(
            phrases: ["scratch that", "delete that"],
            action: "Deletes the last injected utterance (⌘Z). Phrase is stripped from text.",
            status: .stripped
        ),
        CommandEntry(
            phrases: ["all caps"],
            action: "Uppercases the last word. Phrase is stripped from text.",
            status: .stripped
        ),
        CommandEntry(
            phrases: ["period"],
            action: "Inserts a period (.). Phrase is stripped from text.",
            status: .stripped
        ),
        CommandEntry(
            phrases: ["comma"],
            action: "Inserts a comma (,). Phrase is stripped from text.",
            status: .stripped
        ),
        CommandEntry(
            phrases: ["question mark"],
            action: "Inserts a question mark (?). Phrase is stripped from text.",
            status: .stripped
        ),
    ]

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                commandsSection
                notesSection
            }
            .padding()
        }
        .background(hudBackground)
    }

    // MARK: - Sections

    private var commandsSection: some View {
        VCommandSection(title: "VOICE COMMANDS") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(entries) { entry in
                    CommandRow(entry: entry)
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(phosphorGreen.opacity(0.08))
                }
            }
            .overlay(Rectangle().stroke(phosphorGreen.opacity(0.15), lineWidth: 1))
        }
    }

    private var notesSection: some View {
        VCommandSection(title: "USAGE NOTES") {
            VStack(alignment: .leading, spacing: 6) {
                noteRow("Matching is case-insensitive. Say the phrase naturally.")
                noteRow("Phrases are stripped from the injected text whether or not the AX action is implemented.")
                noteRow("Multiple commands in one utterance are all detected, in order.")
                noteRow("Commands marked STRIPPED trigger action in a future update.")
            }
        }
    }

    private func noteRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\u{25B8}")
                .foregroundColor(phosphorGreen.opacity(0.5))
                .font(.caption)
                .fontDesign(.monospaced)
            Text(text)
                .font(.caption)
                .fontDesign(.monospaced)
                .foregroundColor(phosphorGreen.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Command Row

private struct CommandRow: View {
    let entry: VoiceCommandsSettingsView.CommandEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(entry.phrases, id: \.self) { phrase in
                    Text("\"\(phrase)\"")
                        .font(.body)
                        .fontDesign(.monospaced)
                        .foregroundColor(phosphorGreen)
                }
            }
            .frame(minWidth: 140, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.action)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundColor(phosphorGreen.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)

                statusBadge
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch entry.status {
        case .implemented:
            Text("ACTIVE")
                .font(.caption2)
                .fontDesign(.monospaced)
                .foregroundColor(phosphorGreen)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .overlay(Rectangle().stroke(phosphorGreen.opacity(0.5), lineWidth: 1))
        case .stripped:
            Text("STRIPPED")
                .font(.caption2)
                .fontDesign(.monospaced)
                .foregroundColor(phosphorGreen.opacity(0.45))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .overlay(Rectangle().stroke(phosphorGreen.opacity(0.25), lineWidth: 1))
        }
    }
}

// MARK: - Section Container

private struct VCommandSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption)
                .fontDesign(.monospaced)
                .foregroundColor(phosphorGreen.opacity(0.6))

            Rectangle()
                .frame(height: 1)
                .foregroundColor(phosphorGreen.opacity(0.2))

            content()
        }
    }
}
