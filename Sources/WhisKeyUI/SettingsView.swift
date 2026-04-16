import SwiftUI
import WhisKeyCore

private let phosphorGreen = Color(red: 0, green: 1, blue: 0.533)
private let hudBackground  = Color(red: 0.024, green: 0.031, blue: 0.031)

/// Tabbed settings window.
///
/// Tabs: General | Hotkey | Transcription | AI Cleanup | Privacy
public struct SettingsView: View {

    @Bindable private var settings: SettingsManager
    private let modelManager: ModelManager

    public init(settings: SettingsManager, modelManager: ModelManager) {
        self.settings = settings
        self.modelManager = modelManager
    }

    public var body: some View {
        TabView {
            GeneralTab(settings: settings, modelManager: modelManager)
                .tabItem { Label("General", systemImage: "gear") }

            HotkeyTab()
                .tabItem { Label("Hotkey", systemImage: "keyboard") }

            TranscriptionTab(settings: settings)
                .tabItem { Label("Transcription", systemImage: "waveform") }

            AICleanupTab(settings: settings)
                .tabItem { Label("AI Cleanup", systemImage: "sparkles") }

            PrivacyTab()
                .tabItem { Label("Privacy", systemImage: "lock.shield") }
        }
        .frame(width: 480, height: 320)
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
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PhosphorSection(title: "PUSH-TO-TALK HOTKEY") {
                    HStack {
                        Text("CURRENT HOTKEY:")
                            .foregroundColor(phosphorGreen.opacity(0.6))
                        Spacer()
                        Text("RIGHT OPTION (HOLD)")
                            .fontDesign(.monospaced)
                            .foregroundColor(phosphorGreen)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .overlay(
                                Rectangle()
                                    .stroke(phosphorGreen.opacity(0.4), lineWidth: 1)
                            )
                    }
                    Text("Hold to record, release to transcribe and inject.")
                        .font(.caption)
                        .foregroundColor(phosphorGreen.opacity(0.5))
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

                PhosphorSection(title: "CLEANUP OPTIONS") {
                    Toggle("Remove Filler Words", isOn: $settings.removeFillers)
                        .tint(phosphorGreen)
                        .foregroundColor(phosphorGreen)
                    Toggle("Add Punctuation", isOn: $settings.addPunctuation)
                        .tint(phosphorGreen)
                        .foregroundColor(phosphorGreen)
                    Toggle("Raw Mode (skip cleanup)", isOn: $settings.rawMode)
                        .tint(phosphorGreen)
                        .foregroundColor(phosphorGreen)
                }

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
