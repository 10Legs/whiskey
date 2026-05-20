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

    @State private var selectedTab: Int = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        TabView(selection: $selectedTab) {
            GeneralTab(settings: settings, modelManager: modelManager)
                .tabItem { Label("General", systemImage: "gear") }
                .tag(0)

            RecordingTab(settings: settings, bindingStore: bindingStore)
                .tabItem { Label("Recording", systemImage: "keyboard") }
                .tag(1)

            TranscriptionTab(settings: settings)
                .tabItem { Label("Transcription", systemImage: "waveform") }
                .tag(2)

            ModelSettingsView(modelManager: modelManager)
                .tabItem { Label("Models", systemImage: "square.and.arrow.down") }
                .tag(3)

            CustomizationTab(vocabularyStore: vocabularyStore, toneProfileStore: toneProfileStore)
                .tabItem { Label("Customization", systemImage: "slider.horizontal.3") }
                .tag(4)

            if let monitor = networkMonitor {
                PrivacySettingsView(monitor: monitor, hasPulsedRed: $hasPulsedRed)
                    .tabItem { Label("Privacy", systemImage: "lock.shield") }
                    .tag(5)
            } else {
                PrivacyTab()
                    .tabItem { Label("Privacy", systemImage: "lock.shield") }
                    .tag(5)
            }

            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(6)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: selectedTab)
        .frame(width: 540, height: 560)
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
                    Slider(value: $settings.disambiguationWindowMs, in: 250...500, step: 25)
                        .tint(HalideTokens.accentAmber)
                        .accessibilityLabel("Double-tap speed")
                        .accessibilityHint("Controls how quickly you must double-tap.")
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
        HalideSection(title: "AI cleanup") {
            // Row 1: master enable toggle
            Toggle("Enable AI cleanup", isOn: $settings.llmEnabled)
                .tint(HalideTokens.accentAmber)
                .foregroundColor(HalideTokens.textPrimary)
            Text("When off, raw Whisper output is injected verbatim.")
                .font(.caption)
                .foregroundColor(HalideTokens.textSecondary)

            Divider()

            // Sub-controls — faded + disabled when llmEnabled is false
            VStack(alignment: .leading, spacing: 12) {
                // Provider picker
                HStack {
                    Text("Provider")
                        .foregroundColor(HalideTokens.textSecondary)
                    Spacer()
                    Picker("", selection: $settings.llmProviderName) {
                        Text("None").tag("none")
                        Text("LlamaCpp (local)").tag("llamacpp")
                        Text("Ollama (local HTTP)").tag("ollama")
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 180)
                }

                Divider()

                // Cleanup options toggles
                Toggle("Remove filler words", isOn: $settings.removeFillers)
                    .tint(HalideTokens.accentAmber)
                Toggle("Add punctuation", isOn: $settings.addPunctuation)
                    .tint(HalideTokens.accentAmber)
                Toggle("Raw mode (skip LLM, keep options)", isOn: $settings.rawMode)
                    .tint(HalideTokens.accentAmber)

                Divider()

                // Tone style
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tone style")
                        .font(.caption)
                        .foregroundColor(HalideTokens.textSecondary)
                    Picker("", selection: $settings.toneStyle) {
                        ForEach(ToneStyle.allCases, id: \.self) { style in
                            Text(style.rawValue.capitalized).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("Auto-adjusts based on the active application unless overridden.")
                        .font(.caption)
                        .foregroundColor(HalideTokens.textSecondary)
                }
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
                        .foregroundColor(HalideTokens.accentDestructive)
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
                        icon: "mic.fill",
                        title: "Microphone",
                        description: "Required for voice capture.",
                        urlString: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
                    )
                    Divider()
                    PrivacyRow(
                        icon: "accessibility",
                        title: "Accessibility",
                        description: "Required for text injection via AX API.",
                        urlString: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                    )
                    Divider()
                    PrivacyRow(
                        icon: "keyboard",
                        title: "Input Monitoring",
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
    let icon: String
    let title: String
    let description: String
    let urlString: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(HalideTokens.accentAmber)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundColor(HalideTokens.textPrimary)
                Text(description)
                    .font(.caption)
                    .foregroundColor(HalideTokens.textSecondary)
            }
            Spacer()
            Button("Open") {
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
    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(HalideTokens.accentAmber)
                .padding(.bottom, 12)
            Text("WhisKey")
                .font(.title2).fontWeight(.semibold)
                .foregroundColor(HalideTokens.textPrimary)
            Text("Local-first voice transcription for macOS")
                .font(.callout)
                .foregroundColor(HalideTokens.textSecondary)
                .padding(.top, 4)
            Text(versionString)
                .font(.caption)
                .foregroundColor(HalideTokens.textTertiary)
                .padding(.top, 8)
            Spacer()
            Text("© 2026 WhisKey. All rights reserved.")
                .font(.caption2)
                .foregroundColor(HalideTokens.textTertiary)
                .padding(.bottom, HalideTokens.spacing16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HalideTokens.backgroundPrimary)
    }
}
