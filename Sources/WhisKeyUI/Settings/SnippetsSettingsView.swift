// swiftlint:disable file_length
import AppKit
import SwiftUI
import WhisKeyCore

// MARK: - SnippetsSettingsView

// Settings tab content for Voice Snippets (S3-T5).
// Displays the snippet list with add / edit / delete / toggle controls
// and Import / Export JSON buttons. All mutations are dispatched to
// `SnippetStore.shared` (actor-isolated) via `async` tasks.
// swiftlint:disable:next type_body_length
public struct SnippetsSettingsView: View {

    @State private var snippets: [Snippet] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var isShowingAddSheet = false
    @State private var snippetToEdit: Snippet?
    @State private var pendingDeleteID: UUID?
    @State private var autoDismissTask: Task<Void, Never>?
    @State private var overlappingIDs: Set<UUID> = []
    @State private var bannerMessage: String?

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().background(HalideTokens.accentAmber.opacity(0.2))
            if isLoading {
                loadingView
            } else if let err = loadError {
                errorView(message: err)
            } else if snippets.isEmpty {
                emptyStateView
            } else {
                snippetList
            }
        }
        .background(HalideTokens.backgroundPrimary)
        .task { await reload() }
        .sheet(isPresented: $isShowingAddSheet) {
            SnippetEditView(existing: nil) { saved in
                isShowingAddSheet = false
                Task { await save(saved) }
            } onCancel: {
                isShowingAddSheet = false
            }
        }
        .sheet(item: $snippetToEdit) { snippet in
            SnippetEditView(existing: snippet) { saved in
                snippetToEdit = nil
                Task { await save(saved) }
            } onCancel: {
                snippetToEdit = nil
            }
        }
        .overlay(alignment: .bottom) {
            if let msg = bannerMessage {
                Text(msg)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundColor(HalideTokens.backgroundPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(HalideTokens.accentAmber)
                    .cornerRadius(4)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.3), value: bannerMessage)
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button("+ ADD SNIPPET") {
                isShowingAddSheet = true
            }
            .buttonStyle(HalidePrimaryButtonStyle())

            Spacer()

            Button("IMPORT") { Task { await importJSON() } }
                .buttonStyle(HalideSecondaryButtonStyle())

            Button("EXPORT") { Task { await exportJSON() } }
                .buttonStyle(HalideSecondaryButtonStyle())
                .disabled(snippets.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Loading / Error / Empty states

    private var loadingView: some View {
        VStack {
            ProgressView()
                .tint(HalideTokens.accentAmber)
            Text("LOADING...")
                .font(.caption)
                .fontDesign(.monospaced)
                .foregroundColor(HalideTokens.accentAmber.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HalideTokens.backgroundPrimary)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundColor(.orange)
            Text(message)
                .font(.caption)
                .fontDesign(.monospaced)
                .foregroundColor(HalideTokens.accentAmber.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("RESET SNIPPET STORE") {
                Task { await resetStore() }
            }
            .buttonStyle(HalideDestructiveButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HalideTokens.backgroundPrimary)
    }

    private var emptyStateView: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.badge.plus")
                .font(.system(size: 32))
                .foregroundColor(HalideTokens.accentAmber.opacity(0.4))
            Text("No snippets yet.")
                .fontDesign(.monospaced)
                .foregroundColor(HalideTokens.accentAmber.opacity(0.6))
            Text("Tap \"+ Add Snippet\" to create your first voice expansion.")
                .font(.caption)
                .fontDesign(.monospaced)
                .foregroundColor(HalideTokens.accentAmber.opacity(0.4))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HalideTokens.backgroundPrimary)
    }

    // MARK: - Snippet List

    private var snippetList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Column header
                HStack {
                    Text("TRIGGER PHRASE")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("EXPANSION")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("ON")
                        .frame(width: 32, alignment: .center)
                    Text("")
                        .frame(width: 60)
                }
                .font(.system(size: 10))
                .fontDesign(.monospaced)
                .foregroundColor(HalideTokens.accentAmber.opacity(0.5))
                .padding(.horizontal, 16)
                .padding(.vertical, 6)

                Divider().background(HalideTokens.accentAmber.opacity(0.2))

                ForEach(snippets) { snippet in
                    snippetRow(snippet)
                    Divider().background(HalideTokens.accentAmber.opacity(0.1))
                }
            }
        }
        .background(HalideTokens.backgroundPrimary)
    }

    // swiftlint:disable function_body_length
    @ViewBuilder
    private func snippetRow(_ snippet: Snippet) -> some View {
        let isConflicted = overlappingIDs.contains(snippet.id)
        let isPendingDelete = pendingDeleteID == snippet.id

        if isPendingDelete {
            deleteConfirmationRow(snippet)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            if isConflicted {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 10))
                                    .foregroundColor(.orange)
                            }
                            Text(snippet.triggerPhrase)
                                .fontDesign(.monospaced)
                                .foregroundColor(HalideTokens.accentAmber)
                                .lineLimit(1)
                        }
                        if isConflicted {
                            Text("Overlaps with another trigger — longest match wins.")
                                .font(.system(size: 11))
                                .fontDesign(.monospaced)
                                .foregroundColor(.orange.opacity(0.8))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(expansionPreview(snippet.expansionText))
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundColor(HalideTokens.accentAmber.opacity(0.6))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Toggle("", isOn: Binding(
                        get: { snippet.isEnabled },
                        set: { newValue in Task { await toggle(snippet, enabled: newValue) } }
                    ))
                    .toggleStyle(.switch)
                    .tint(HalideTokens.accentAmber)
                    .labelsHidden()
                    .frame(width: 40)

                    HStack(spacing: 4) {
                        Button {
                            snippetToEdit = snippet
                        } label: {
                            Image(systemName: "pencil")
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(HalideTokens.accentAmber)
                        .accessibilityLabel("Edit \(snippet.triggerPhrase)")
                        .help("Edit snippet")

                        Button {
                            beginDelete(snippet)
                        } label: {
                            Image(systemName: "trash")
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.red.opacity(0.7))
                        .accessibilityLabel("Delete \(snippet.triggerPhrase)")
                        .help("Delete snippet")
                    }
                    .frame(width: 56)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Snippet: \(snippet.triggerPhrase), \(snippet.isEnabled ? "enabled" : "disabled")")
            .background(HalideTokens.backgroundPrimary)
        }
    }
    // swiftlint:enable function_body_length

    private func deleteConfirmationRow(_ snippet: Snippet) -> some View {
        HStack {
            Text("Delete \"\(snippet.triggerPhrase)\"?")
                .font(.caption)
                .fontDesign(.monospaced)
                .foregroundColor(HalideTokens.accentAmber)
                .lineLimit(1)
            Spacer()
            Button("CANCEL") { cancelDelete() }
                .buttonStyle(HalideSecondaryButtonStyle())
            Button("DELETE") {
                autoDismissTask?.cancel()
                Task { await confirmDelete(snippet.id) }
            }
            .buttonStyle(HalideDestructiveButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(HalideTokens.backgroundPrimary)
    }

    // MARK: - Actions

    private func reload() async {
        isLoading = true
        loadError = nil
        do {
            let loaded = try await SnippetStore.shared.loadAll()
            let pairs = await SnippetStore.shared.overlappingTriggers()
            snippets = loaded
            overlappingIDs = Set(pairs.flatMap { [$0.0, $0.1] })
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func save(_ snippet: Snippet) async {
        do {
            try await SnippetStore.shared.save(snippet)
            await reload()
        } catch {
            showBanner("Save failed: \(error.localizedDescription)")
        }
    }

    private func toggle(_ snippet: Snippet, enabled: Bool) async {
        var updated = snippet
        updated.isEnabled = enabled
        await save(updated)
    }

    private func beginDelete(_ snippet: Snippet) {
        autoDismissTask?.cancel()
        pendingDeleteID = snippet.id
        autoDismissTask = Task {
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled {
                pendingDeleteID = nil
            }
        }
    }

    private func cancelDelete() {
        autoDismissTask?.cancel()
        pendingDeleteID = nil
    }

    private func confirmDelete(_ id: UUID) async {
        pendingDeleteID = nil
        do {
            try await SnippetStore.shared.delete(id: id)
            await reload()
        } catch {
            showBanner("Delete failed: \(error.localizedDescription)")
        }
    }

    private func resetStore() async {
        do {
            try await SnippetStore.shared.reset()
            await reload()
        } catch {
            showBanner("Reset failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Import / Export

    @MainActor
    private func exportJSON() async {
        let data: Data
        do {
            data = try await SnippetStore.shared.exportJSON()
        } catch {
            showBanner("Export failed: \(error.localizedDescription)")
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: Date())

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "whiskey-snippets-\(dateStr).json"
        panel.allowedContentTypes = [.json]
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Export Failed"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    @MainActor
    private func importJSON() async {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            showAlert(title: "Import Failed", message: error.localizedDescription)
            return
        }

        // Preview the import contents before applying.
        let previewFile: SnippetsImportPreview
        do {
            previewFile = try SnippetsImportPreview(data: data)
        } catch {
            showAlert(title: "Could not import", message: error.localizedDescription)
            return
        }

        guard await showImportPreview(previewFile) else { return }

        do {
            let result = try await SnippetStore.shared.importJSON(data, mode: .merge)
            await reload()
            showBanner("\(result.added) snippet(s) imported. \(result.skipped) duplicate(s) skipped.")
        } catch {
            showAlert(title: "Import Failed", message: error.localizedDescription)
        }
    }

    @MainActor
    private func showImportPreview(_ preview: SnippetsImportPreview) async -> Bool {
        let alert = NSAlert()
        alert.messageText = "Import \(preview.snippets.count) Snippet(s)"
        let lines = preview.snippets.prefix(5).map { entry in
            "\u{2022} \(entry.triggerPhrase) → \(expansionPreview(entry.expansionText))"
        }.joined(separator: "\n")
        let more = preview.snippets.count > 5 ? "\n... and \(preview.snippets.count - 5) more" : ""
        alert.informativeText = lines + more + "\n\nDuplicate triggers will be skipped."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Import All")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    @MainActor
    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    // MARK: - Helpers

    private func expansionPreview(_ text: String) -> String {
        let clean = text.replacingOccurrences(of: "\n", with: " ")
        guard clean.count > 20 else { return clean }
        return String(clean.prefix(20)) + "…"
    }

    @MainActor
    private func showBanner(_ message: String) {
        withAnimation {
            bannerMessage = message
        }
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation { bannerMessage = nil }
        }
    }
}

// MARK: - SnippetEditView

private struct SnippetEditView: View {

    let existing: Snippet?
    let onSave: (Snippet) -> Void
    let onCancel: () -> Void

    @State private var triggerPhrase: String
    @State private var expansionText: String
    @State private var previewEnabled: Bool
    @State private var attemptedSave = false

    init(existing: Snippet?, onSave: @escaping (Snippet) -> Void, onCancel: @escaping () -> Void) {
        self.existing = existing
        self.onSave = onSave
        self.onCancel = onCancel
        _triggerPhrase = State(initialValue: existing?.triggerPhrase ?? "")
        _expansionText = State(initialValue: existing?.expansionText ?? "")
        _previewEnabled = State(initialValue: existing?.previewNotificationEnabled ?? true)
    }

    private var wordCount: Int {
        triggerPhrase.split(whereSeparator: \.isWhitespace).count
    }

    private var triggerIsValid: Bool {
        wordCount >= 3 && !triggerPhrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSave: Bool {
        triggerIsValid && !expansionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasVariableTokens: Bool {
        expansionText.contains("{") && expansionText.contains("}")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title
            Text(existing == nil ? "ADD SNIPPET" : "EDIT SNIPPET")
                .font(.headline)
                .fontDesign(.monospaced)
                .foregroundColor(HalideTokens.accentAmber)

            Divider().background(HalideTokens.accentAmber.opacity(0.3))

            // Trigger Phrase
            VStack(alignment: .leading, spacing: 4) {
                Text("TRIGGER PHRASE")
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundColor(HalideTokens.accentAmber.opacity(0.6))
                TextField("insert email signature", text: $triggerPhrase)
                    .halideTextField()
                Text("Say this phrase to trigger the expansion.")
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundColor(HalideTokens.accentAmber.opacity(0.4))
                if attemptedSave && !triggerIsValid {
                    Text("Trigger must be at least 3 words to reduce accidental matches. (\(wordCount) word(s))")
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundColor(.orange)
                }
            }

            // Expansion Text
            VStack(alignment: .leading, spacing: 4) {
                Text("EXPANSION TEXT")
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundColor(HalideTokens.accentAmber.opacity(0.6))
                TextEditor(text: $expansionText)
                    .font(.body)
                    .fontDesign(.monospaced)
                    .foregroundColor(HalideTokens.accentAmber)
                    .background(HalideTokens.backgroundPrimary)
                    .frame(height: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(HalideTokens.accentAmber.opacity(0.3), lineWidth: 1)
                    )
                if hasVariableTokens {
                    Text("Variable substitution ({date}, {time}) is not yet supported and will be treated as literal text.")
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundColor(HalideTokens.accentAmber.opacity(0.5))
                }
            }

            // Live Preview
            VStack(alignment: .leading, spacing: 4) {
                Text("LIVE PREVIEW")
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundColor(HalideTokens.accentAmber.opacity(0.6))
                ScrollView(.vertical) {
                    Text(expansionText.isEmpty ? " " : expansionText)
                        .font(.body)
                        .fontDesign(.monospaced)
                        .foregroundColor(HalideTokens.accentAmber.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(height: 120)
                .background(HalideTokens.accentAmber.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(HalideTokens.accentAmber.opacity(0.4), lineWidth: 2)
                )
                .accessibilityLabel("Expansion preview: \(String(expansionText.prefix(60)))")
            }

            // Preview notification toggle
            Toggle("Show preview notification before first use", isOn: $previewEnabled)
                .toggleStyle(.switch)
                .tint(HalideTokens.accentAmber)
                .foregroundColor(HalideTokens.textPrimary)

            Divider().background(HalideTokens.accentAmber.opacity(0.3))

            // Buttons
            HStack {
                Spacer()
                Button("CANCEL") { onCancel() }
                    .buttonStyle(HalideSecondaryButtonStyle())
                Button("SAVE SNIPPET") {
                    attemptedSave = true
                    guard canSave else { return }
                    var snippet = existing ?? Snippet(
                        triggerPhrase: triggerPhrase,
                        expansionText: expansionText
                    )
                    snippet.triggerPhrase = triggerPhrase
                    snippet.expansionText = expansionText
                    snippet.previewNotificationEnabled = previewEnabled
                    onSave(snippet)
                }
                .buttonStyle(HalidePrimaryButtonStyle())
                .disabled(!canSave)
                .opacity(canSave ? 1.0 : 0.4)
            }
        }
        .padding(20)
        .frame(width: 480)
        .background(HalideTokens.backgroundPrimary)
    }
}

// MARK: - Import Preview Helper

/// Thin value type for previewing import file contents before applying them.
private struct SnippetsImportPreview {

    struct Entry {
        let triggerPhrase: String
        let expansionText: String
    }

    let snippets: [Entry]

    private struct File: Decodable {
        let version: Int
        let snippets: [Row]

        struct Row: Decodable {
            let triggerPhrase: String
            let expansionText: String

            // swiftlint:disable:next nesting
            private enum CodingKeys: String, CodingKey {
                case triggerPhrase, expansionText
            }
        }
    }

    init(data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(File.self, from: data)
        guard file.version == 1 else {
            throw SnippetStoreError.importFailed(
                "This file was exported from a newer version of WhisKey (schema v\(file.version)). " +
                "Please update the app."
            )
        }
        guard !file.snippets.isEmpty else {
            throw SnippetStoreError.importFailed("The import file contains no valid snippets.")
        }
        self.snippets = file.snippets.map { Entry(triggerPhrase: $0.triggerPhrase, expansionText: $0.expansionText) }
    }
}
