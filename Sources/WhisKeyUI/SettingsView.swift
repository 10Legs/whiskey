import SwiftUI
import WhisKeyCore

private let phosphorGreen = Color(red: 0, green: 1, blue: 0.533)
private let hudBackground  = Color(red: 0.024, green: 0.031, blue: 0.031)

/// Tabbed settings window.
///
/// Tabs: General | Models | Hotkey | Transcription | AI Cleanup | Snippets | Privacy | Hotkeys
public struct SettingsView: View {

    @Bindable private var settings: SettingsManager
    private let modelManager: ModelManager
    // S3-T3: Live egress monitor injected from AppDelegate. Optional so previews compile.
    private let networkMonitor: NetworkActivityMonitor?
    @Binding private var hasPulsedRed: Bool
    // S3-T6: Multi-hotkey binding store powering the Hotkeys tab.
    private let bindingStore: HotkeyBindingStore

    public init(
        settings: SettingsManager,
        modelManager: ModelManager,
        networkMonitor: NetworkActivityMonitor? = nil,
        hasPulsedRed: Binding<Bool> = .constant(false),
        bindingStore: HotkeyBindingStore
    ) {
        self.settings = settings
        self.modelManager = modelManager
        self.networkMonitor = networkMonitor
        self._hasPulsedRed = hasPulsedRed
        self.bindingStore = bindingStore
    }

    public var body: some View {
        TabView {
            GeneralTab(settings: settings, modelManager: modelManager)
                .tabItem { Label("General", systemImage: "gear") }

            ModelSettingsView(modelManager: modelManager)
                .tabItem { Label("Models", systemImage: "square.and.arrow.down") }

            HotkeyTab(settings: settings)
                .tabItem { Label("Hotkey", systemImage: "keyboard") }

            TranscriptionTab(settings: settings)
                .tabItem { Label("Transcription", systemImage: "waveform") }

            AICleanupTab(settings: settings)
                .tabItem { Label("AI Cleanup", systemImage: "sparkles") }

            // Voice Snippets — trigger-phrase text expansion (S3-T5).
            SnippetsSettingsView()
                .tabItem { Label("Snippets", systemImage: "text.badge.plus") }

            // Network egress audit log and zero-egress claim indicator (S3-T3).
            if let monitor = networkMonitor {
                PrivacySettingsView(monitor: monitor, hasPulsedRed: $hasPulsedRed)
                    .tabItem { Label("Privacy", systemImage: "lock.shield") }
            } else {
                PrivacyTab()
                    .tabItem { Label("Privacy", systemImage: "lock.shield") }
            }

            // S3-T6: Multi-hotkey bindings tab.
            HotkeySettingsView(store: bindingStore)
                .tabItem { Label("Hotkeys", systemImage: "keyboard.badge.ellipsis") }
        }
        .frame(width: 520, height: 460)
        .background(hudBackground)
        .accentColor(phosphorGreen)
        .fontDesign(.monospaced)
    }
}

// MARK: - General Tab

private struct GeneralTab: View {
    @Bindable var settings: SettingsManager
    let modelManager: ModelManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PhosphorSection(title: "STARTUP") {
                    Toggle("Launch at Login", isOn: .constant(false))
                        .disabled(true)
                        .tint(phosphorGreen)
                        .foregroundColor(phosphorGreen.opacity(0.4))
                        .help("Coming soon — requires SMAppService integration.")
                }

                PhosphorSection(title: "WHISPER MODEL") {
                    ModelPickerView(modelManager: modelManager)
                }

                PhosphorSection(title: "OUTPUT MODE") {
                    Picker("Output Mode", selection: $settings.outputMode) {
                        Text("Active Window").tag(OutputMode.activeWindow)
                        Text("Clipboard").tag(OutputMode.clipboard)
                        Text("Both").tag(OutputMode.both)
                    }
                    .pickerStyle(.segmented)
                    .accentColor(phosphorGreen)
                    Text(
                        "Active Window injects into focused field. Clipboard copies without injecting." +
                        " Both does both."
                    )
                        .font(.caption)
                        .foregroundColor(phosphorGreen.opacity(0.5))
                }
            }
            .padding()
        }
        .background(hudBackground)
    }
}

// MARK: - Hotkey Tab

private struct HotkeyTab: View {
    @Bindable var settings: SettingsManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PhosphorSection(title: "PUSH-TO-TALK HOTKEY") {
                    HStack {
                        Text("CURRENT HOTKEY:")
                            .foregroundColor(phosphorGreen.opacity(0.6))
                        Spacer()
                        Text("RIGHT OPTION")
                            .fontDesign(.monospaced)
                            .foregroundColor(phosphorGreen)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .overlay(
                                Rectangle()
                                    .stroke(phosphorGreen.opacity(0.4), lineWidth: 1)
                            )
                    }
                    Text("Hold to record, release to transcribe. Double-tap to start hands-free recording.")
                        .font(.caption)
                        .foregroundColor(phosphorGreen.opacity(0.5))
                }

                PhosphorSection(title: "INTERACTION MODE") {
                    Toggle("Enable hands-free mode (double-tap)", isOn: $settings.handsFreeEnabled)
                        .tint(phosphorGreen)
                        .foregroundColor(phosphorGreen)
                        .accessibilityLabel("Enable hands-free mode")
                        .accessibilityHint(
                            "Double-tap the hotkey to start recording hands-free. Tap again to stop."
                        )
                    Text("Double-tap the hotkey to start recording hands-free. Tap again to stop.")
                        .font(.caption)
                        .foregroundColor(phosphorGreen.opacity(0.5))

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("DOUBLE-TAP WINDOW")
                                .font(.caption)
                                .fontDesign(.monospaced)
                                .foregroundColor(phosphorGreen.opacity(0.6))
                            Spacer()
                            Text("\(Int(settings.disambiguationWindowMs)) ms")
                                .font(.caption)
                                .fontDesign(.monospaced)
                                .foregroundColor(phosphorGreen)
                        }
                        HStack(spacing: 8) {
                            Text("FASTER")
                                .font(.caption2)
                                .fontDesign(.monospaced)
                                .foregroundColor(phosphorGreen.opacity(0.45))
                            Slider(
                                value: $settings.disambiguationWindowMs,
                                in: 250...500,
                                step: 25
                            )
                            .tint(phosphorGreen)
                            .accessibilityLabel("Double-tap speed")
                            .accessibilityHint(
                                "Controls how quickly you must double-tap. Increase if double-taps aren't registering."
                            )
                            Text("SLOWER")
                                .font(.caption2)
                                .fontDesign(.monospaced)
                                .foregroundColor(phosphorGreen.opacity(0.45))
                        }
                        Text(
                            "Controls how quickly you must double-tap. " +
                            "Increase if your double-taps aren't registering."
                        )
                        .font(.caption)
                        .foregroundColor(phosphorGreen.opacity(0.5))
                    }
                    .opacity(settings.handsFreeEnabled ? 1 : 0.35)
                    .disabled(!settings.handsFreeEnabled)
                }
            }
            .padding()
        }
        .background(hudBackground)
    }
}

// MARK: - Transcription Tab

private struct TranscriptionTab: View {
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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PhosphorSection(title: "LANGUAGE") {
                    Picker("Language Hint", selection: $settings.languageHint) {
                        ForEach(Self.languages, id: \.1) { name, code in
                            Text(name).tag(code)
                        }
                    }
                    .pickerStyle(.menu)
                    .accentColor(phosphorGreen)
                    .foregroundColor(phosphorGreen)
                    Text("Providing a language hint improves accuracy when you know the spoken language.")
                        .font(.caption)
                        .foregroundColor(phosphorGreen.opacity(0.5))
                }
            }
            .padding()
        }
        .background(hudBackground)
    }
}

// MARK: - AI Cleanup Tab

private struct AICleanupTab: View {
    @Bindable var settings: SettingsManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PhosphorSection(title: "AI CLEANUP") {
                    Toggle("Enable AI Cleanup", isOn: $settings.llmEnabled)
                        .tint(phosphorGreen)
                        .foregroundColor(phosphorGreen)
                    Text("When off, raw Whisper output is injected verbatim — no LLM runs.")
                        .font(.caption)
                        .foregroundColor(phosphorGreen.opacity(0.5))
                }

                PhosphorSection(title: "LLM PROVIDER") {
                    Picker("Provider", selection: $settings.llmProviderName) {
                        Text("None (raw transcript)").tag("none")
                        Text("LlamaCpp (local)").tag("llamacpp")
                        Text("Ollama (local HTTP)").tag("ollama")
                    }
                    .pickerStyle(.menu)
                    .accentColor(phosphorGreen)
                    .foregroundColor(phosphorGreen)
                }
                .opacity(settings.llmEnabled ? 1 : 0.35)
                .disabled(!settings.llmEnabled)

                PhosphorSection(title: "CLEANUP OPTIONS") {
                    Toggle("Remove Filler Words", isOn: $settings.removeFillers)
                        .tint(phosphorGreen)
                        .foregroundColor(phosphorGreen)
                    Toggle("Add Punctuation", isOn: $settings.addPunctuation)
                        .tint(phosphorGreen)
                        .foregroundColor(phosphorGreen)
                    Toggle("Raw Mode (skip LLM, keep options)", isOn: $settings.rawMode)
                        .tint(phosphorGreen)
                        .foregroundColor(phosphorGreen)
                }
                .opacity(settings.llmEnabled ? 1 : 0.35)
                .disabled(!settings.llmEnabled)

                PhosphorSection(title: "TONE STYLE") {
                    Picker("Default Tone", selection: $settings.toneStyle) {
                        ForEach(ToneStyle.allCases, id: \.self) { style in
                            Text(style.rawValue.uppercased()).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accentColor(phosphorGreen)
                    Text("Tone auto-adjusts based on the active application unless overridden here.")
                        .font(.caption)
                        .foregroundColor(phosphorGreen.opacity(0.5))
                }
                .opacity(settings.llmEnabled ? 1 : 0.35)
                .disabled(!settings.llmEnabled)
            }
            .padding()
        }
        .background(hudBackground)
    }
}

// MARK: - Privacy Tab

private struct PrivacyTab: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PhosphorSection(title: "REQUIRED PERMISSIONS") {
                    PrivacyRow(
                        title: "MICROPHONE",
                        description: "Required for voice capture.",
                        urlString: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
                    )
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(phosphorGreen.opacity(0.15))
                    PrivacyRow(
                        title: "ACCESSIBILITY",
                        description: "Required for text injection via AX API.",
                        urlString: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                    )
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(phosphorGreen.opacity(0.15))
                    PrivacyRow(
                        title: "INPUT MONITORING",
                        description: "Required for global hotkey (Right Option).",
                        urlString: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
                    )
                }
            }
            .padding()
        }
        .background(hudBackground)
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
                    .foregroundColor(phosphorGreen)
                Text(description)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundColor(phosphorGreen.opacity(0.5))
            }
            Spacer()
            Button("OPEN") {
                if let url = URL(string: urlString) {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(PhosphorButtonStyle())
        }
    }
}

// MARK: - Shared Phosphor Components

private struct PhosphorSection<Content: View>: View {
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
