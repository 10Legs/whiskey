// swiftlint:disable file_length
import SwiftUI
import WhisKeyCore

/// Tabbed settings window.
///
/// Tabs: General | Recording | Transcription | Models | Customization | Privacy | About
public struct SettingsView: View {

    @Bindable private var settings: SettingsManager
    private let modelManager: ModelManager
    private let networkMonitor: NetworkActivityMonitor?
    @Binding private var hasPulsedRed: Bool
    private let bindingStore: HotkeyBindingStore
    private let vocabularyStore: PersonalVocabularyStore
    private let toneProfileStore: AppToneProfileStore

    public init(
        settings: SettingsManager,
        modelManager: ModelManager,
        networkMonitor: NetworkActivityMonitor? = nil,
        hasPulsedRed: Binding<Bool> = .constant(false),
        bindingStore: HotkeyBindingStore,
        vocabularyStore: PersonalVocabularyStore = .shared,
        toneProfileStore: AppToneProfileStore = .shared
    ) {
        self.settings = settings
        self.modelManager = modelManager
        self.networkMonitor = networkMonitor
        self._hasPulsedRed = hasPulsedRed
        self.bindingStore = bindingStore
        self.vocabularyStore = vocabularyStore
        self.toneProfileStore = toneProfileStore
    }

    public var body: some View {
        TabView {
            GeneralTab(settings: settings, modelManager: modelManager)
                .tabItem { Label("General", systemImage: "gear") }

            RecordingTab(settings: settings, bindingStore: bindingStore)
                .tabItem { Label("Recording", systemImage: "keyboard") }

            TranscriptionTab(settings: settings)
                .tabItem { Label("Transcription", systemImage: "waveform") }

            ModelSettingsView(modelManager: modelManager)
                .tabItem { Label("Models", systemImage: "square.and.arrow.down") }

            CustomizationTab(vocabularyStore: vocabularyStore, toneProfileStore: toneProfileStore)
                .tabItem { Label("Customization", systemImage: "slider.horizontal.3") }

            if let monitor = networkMonitor {
                PrivacySettingsView(monitor: monitor, hasPulsedRed: $hasPulsedRed)
                    .tabItem { Label("Privacy", systemImage: "lock.shield") }
            } else {
                PrivacyTab()
                    .tabItem { Label("Privacy", systemImage: "lock.shield") }
            }

            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 520)
        .background(HalideTokens.backgroundPrimary)
        .accentColor(HalideTokens.accentAmber)
    }
}

// MARK: - General Tab

private struct GeneralTab: View {
    @Bindable var settings: SettingsManager
    let modelManager: ModelManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HalideSection(title: "Startup") {
                    Toggle("Launch at Login", isOn: .constant(false))
                        .disabled(true)
                        .tint(HalideTokens.accentAmber)
                        .foregroundColor(HalideTokens.textPrimary)
                        .help("Coming soon — requires SMAppService integration.")
                }

                HalideSection(title: "Whisper model") {
                    ModelPickerView(modelManager: modelManager)
                }

                HalideSection(title: "Output mode") {
                    Picker("Output Mode", selection: $settings.outputMode) {
                        Text("Active Window").tag(OutputMode.activeWindow)
                        Text("Clipboard").tag(OutputMode.clipboard)
                        Text("Both").tag(OutputMode.both)
                    }
                    .pickerStyle(.segmented)
                    .accentColor(HalideTokens.accentAmber)
                    Text(
                        "Active Window injects into focused field. Clipboard copies without injecting." +
                        " Both does both."
                    )
                        .font(.caption)
                        .foregroundColor(HalideTokens.textSecondary)
                }
            }
            .padding()
        }
        .background(HalideTokens.backgroundPrimary)
    }
}

// MARK: - Recording Tab

private struct RecordingTab: View {
    @Bindable var settings: SettingsManager
    let bindingStore: HotkeyBindingStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HotkeySection(settings: settings)
                HalideSection(title: "Hotkey bindings") {
                    HotkeySettingsView(store: bindingStore)
                }
                HalideSection(title: "Voice commands") {
                    VoiceCommandsSettingsView()
                }
            }
            .padding()
        }
        .background(HalideTokens.backgroundPrimary)
    }
}

// MARK: - Hotkey Section (formerly HotkeyTab)

private struct HotkeySection: View {
    @Bindable var settings: SettingsManager

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HalideSection(title: "Push-to-talk hotkey") {
                HStack {
                    Text("Current hotkey:")
                        .foregroundColor(HalideTokens.textSecondary)
                    Spacer()
                    Text("RIGHT OPTION")
                        .fontDesign(.monospaced)
                        .foregroundColor(HalideTokens.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: HalideTokens.radiusSmall)
                                .stroke(HalideTokens.borderDefault, lineWidth: 1)
                        )
                }
                Text("Hold to record, release to transcribe. Double-tap to start hands-free recording.")
                    .font(.caption)
                    .foregroundColor(HalideTokens.textSecondary)
            }

            HalideSection(title: "Interaction mode") {
                Toggle("Enable hands-free mode (double-tap)", isOn: $settings.handsFreeEnabled)
                    .tint(HalideTokens.accentAmber)
                    .foregroundColor(HalideTokens.textPrimary)
                    .accessibilityLabel("Enable hands-free mode")
                    .accessibilityHint(
                        "Double-tap the hotkey to start recording hands-free. Tap again to stop."
                    )
                Text("Double-tap the hotkey to start recording hands-free. Tap again to stop.")
                    .font(.caption)
                    .foregroundColor(HalideTokens.textSecondary)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Double-tap window")
                            .font(.caption)
                            .foregroundColor(HalideTokens.textSecondary)
                        Spacer()
                        Text("\(Int(settings.disambiguationWindowMs)) ms")
                            .font(.caption)
                            .fontDesign(.monospaced)
                            .foregroundColor(HalideTokens.accentAmber)
                    }
                    HStack(spacing: 8) {
                        Text("FASTER")
                            .font(.caption2)
                            .foregroundColor(HalideTokens.textTertiary)
                        Slider(
                            value: $settings.disambiguationWindowMs,
                            in: 250...500,
                            step: 25
                        )
                        .tint(HalideTokens.accentAmber)
                        .accessibilityLabel("Double-tap speed")
                        .accessibilityHint(
                            "Controls how quickly you must double-tap. Increase if double-taps aren't registering."
                        )
                        Text("SLOWER")
                            .font(.caption2)
                            .foregroundColor(HalideTokens.textTertiary)
                    }
                    Text(
                        "Controls how quickly you must double-tap. " +
                        "Increase if your double-taps aren't registering."
                    )
                    .font(.caption)
                    .foregroundColor(HalideTokens.textSecondary)
                }
                .opacity(settings.handsFreeEnabled ? 1 : 0.35)
                .disabled(!settings.handsFreeEnabled)
            }
        }
    }
}

// MARK: - Transcription Tab

private struct TranscriptionTab: View {
    @Bindable var settings: SettingsManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                LanguageSection(settings: settings)
                AICleanupSection(settings: settings)
            }
            .padding()
        }
        .background(HalideTokens.backgroundPrimary)
    }
}

// MARK: - Language Section (formerly TranscriptionTab)

private struct LanguageSection: View {
    @Bindable var settings: SettingsManager

    private static let languages: [(String, String?)] = [
        ("Auto-detect", nil),
        ("English", "en"),
        ("Spanish", "es"),
        ("French", "fr"),
        ("German", "de"),
        ("Italian", "it"),
        ("Portuguese", "pt"),
        ("Japanese", "ja"),
        ("Chinese", "zh"),
        ("Korean", "ko")
    ]

    var body: some View {
        HalideSection(title: "Language") {
            Picker("Language Hint", selection: $settings.languageHint) {
                ForEach(Self.languages, id: \.1) { name, code in
                    Text(name).tag(code)
                }
            }
            .pickerStyle(.menu)
            .accentColor(HalideTokens.accentAmber)
            .foregroundColor(HalideTokens.accentAmber)
            Text("Providing a language hint improves accuracy when you know the spoken language.")
                .font(.caption)
                .foregroundColor(HalideTokens.textSecondary)
        }
    }
}

// MARK: - AI Cleanup Section (formerly AICleanupTab)

private struct AICleanupSection: View {
    @Bindable var settings: SettingsManager

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HalideSection(title: "AI cleanup") {
                Toggle("Enable AI Cleanup", isOn: $settings.llmEnabled)
                    .tint(HalideTokens.accentAmber)
                    .foregroundColor(HalideTokens.textPrimary)
                Text("When off, raw Whisper output is injected verbatim — no LLM runs.")
                    .font(.caption)
                    .foregroundColor(HalideTokens.textSecondary)
            }

            HalideSection(title: "LLM provider") {
                Picker("Provider", selection: $settings.llmProviderName) {
                    Text("None (raw transcript)").tag("none")
                    Text("LlamaCpp (local)").tag("llamacpp")
                    Text("Ollama (local HTTP)").tag("ollama")
                }
                .pickerStyle(.menu)
                .accentColor(HalideTokens.accentAmber)
                .foregroundColor(HalideTokens.accentAmber)
            }
            .opacity(settings.llmEnabled ? 1 : 0.35)
            .disabled(!settings.llmEnabled)

            HalideSection(title: "Cleanup options") {
                Toggle("Remove Filler Words", isOn: $settings.removeFillers)
                    .tint(HalideTokens.accentAmber)
                    .foregroundColor(HalideTokens.textPrimary)
                Toggle("Add Punctuation", isOn: $settings.addPunctuation)
                    .tint(HalideTokens.accentAmber)
                    .foregroundColor(HalideTokens.textPrimary)
                Toggle("Raw Mode (skip LLM, keep options)", isOn: $settings.rawMode)
                    .tint(HalideTokens.accentAmber)
                    .foregroundColor(HalideTokens.textPrimary)
            }
            .opacity(settings.llmEnabled ? 1 : 0.35)
            .disabled(!settings.llmEnabled)

            HalideSection(title: "Tone style") {
                Picker("Default Tone", selection: $settings.toneStyle) {
                    ForEach(ToneStyle.allCases, id: \.self) { style in
                        Text(style.rawValue.uppercased()).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .accentColor(HalideTokens.accentAmber)
                Text("Tone auto-adjusts based on the active application unless overridden here.")
                    .font(.caption)
                    .foregroundColor(HalideTokens.textSecondary)
            }
            .opacity(settings.llmEnabled ? 1 : 0.35)
            .disabled(!settings.llmEnabled)
        }
    }
}

// MARK: - Customization Tab

private struct CustomizationTab: View {
    @ObservedObject var vocabularyStore: PersonalVocabularyStore
    @Bindable var toneProfileStore: AppToneProfileStore

    init(vocabularyStore: PersonalVocabularyStore, toneProfileStore: AppToneProfileStore) {
        self.vocabularyStore = vocabularyStore
        self.toneProfileStore = toneProfileStore
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VocabularyContent(store: vocabularyStore)
                HalideSection(title: "Text snippets") {
                    SnippetsSettingsView()
                }
                ToneProfilesSettingsView(store: toneProfileStore)
            }
            .padding()
        }
        .background(HalideTokens.backgroundPrimary)
    }
}

// MARK: - Vocabulary Content (inlined from VocabularyTab)

private struct VocabularyContent: View {
    @ObservedObject var store: PersonalVocabularyStore
    @State private var newTerm: String = ""
    @State private var errorMessage: String?

    private let maxTerms = PersonalVocabularyStore.maximumTermCount

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HalideSection(title: "Personal vocabulary") {
                Text(
                    "Terms are passed to Whisper as a prompt hint, improving accuracy for " +
                    "proper nouns, product names, and domain-specific words."
                )
                .font(.caption)
                .foregroundColor(HalideTokens.textSecondary)
            }

            HalideSection(title: "Add term") {
                HStack(spacing: 8) {
                    TextField("e.g. SwiftUI, Xcode, WhisKey", text: $newTerm)
                        .halideTextField()
                        .onSubmit { commitNewTerm() }

                    Button("ADD") { commitNewTerm() }
                        .buttonStyle(HalidePrimaryButtonStyle())
                        .disabled(newTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let msg = errorMessage {
                    Text(msg)
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundColor(.red.opacity(0.85))
                }
            }

            HalideSection(title: "Terms (\(store.terms.count) / \(maxTerms))") {
                if store.terms.isEmpty {
                    Text("No vocabulary terms added.")
                        .font(.caption)
                        .foregroundColor(HalideTokens.textSecondary)
                        .padding(.vertical, 4)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(store.terms, id: \.self) { term in
                            HStack {
                                Text(term)
                                    .foregroundColor(HalideTokens.textPrimary)
                                Spacer()
                                Button {
                                    store.remove(term)
                                    errorMessage = nil
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.caption)
                                        .foregroundColor(HalideTokens.textSecondary.opacity(0.6))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove \(term)")
                            }
                            .padding(.vertical, 5)
                            .padding(.horizontal, 4)

                            Divider()
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: HalideTokens.radiusSmall)
                            .stroke(HalideTokens.borderSubtle, lineWidth: 1)
                    )
                }
            }
        }
    }

    private func commitNewTerm() {
        do {
            try store.add(newTerm)
            newTerm = ""
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Privacy Tab

private struct PrivacyTab: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HalideSection(title: "Required permissions") {
                    PrivacyRow(
                        title: "MICROPHONE",
                        description: "Required for voice capture.",
                        urlString: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
                    )
                    Divider()
                    PrivacyRow(
                        title: "ACCESSIBILITY",
                        description: "Required for text injection via AX API.",
                        urlString: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                    )
                    Divider()
                    PrivacyRow(
                        title: "INPUT MONITORING",
                        description: "Required for global hotkey (Right Option).",
                        urlString: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
                    )
                }
            }
            .padding()
        }
        .background(HalideTokens.backgroundPrimary)
    }
}

private struct PrivacyRow: View {
    let title: String
    let description: String
    let urlString: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .fontDesign(.monospaced)
                    .foregroundColor(HalideTokens.accentAmber)
                Text(description)
                    .font(.caption)
                    .foregroundColor(HalideTokens.textSecondary)
            }
            Spacer()
            Button("OPEN") {
                if let url = URL(string: urlString) {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(HalideSecondaryButtonStyle())
        }
    }
}

// MARK: - About Tab

private struct AboutTab: View {
    var body: some View {
        VStack(spacing: HalideTokens.spacing16) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 48))
                .foregroundColor(HalideTokens.accentAmber)
            Text("WhisKey")
                .font(.title2).fontWeight(.semibold)
                .foregroundColor(HalideTokens.textPrimary)
            Text("Local-first voice transcription for macOS")
                .font(.callout)
                .foregroundColor(HalideTokens.textSecondary)
            Spacer()
        }
        .padding(.top, HalideTokens.spacing24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HalideTokens.backgroundPrimary)
    }
}
